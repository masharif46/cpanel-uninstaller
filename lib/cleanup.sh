#!/usr/bin/env bash
# lib/cleanup.sh - remove cPanel files, configs, logs, cron, repos

# ------------------------------------------------------------------------------
# Directory removal
# ------------------------------------------------------------------------------
CPANEL_DIRS=(
    /usr/local/cpanel
    /var/cpanel
    /etc/cpanel
    /scripts
    /root/cpanel3-skel
    /root/.cpanel
    /root/cpanel_profiles
    /usr/share/cpanel-whm-includes
    /usr/local/apache
    /var/cpanel-ccs
    /var/cpanel-roundcube
    /var/cpanel-dovecot-solr
    /var/cpdavd
    /var/cpanel-horde
    /opt/cpanel
    /opt/ea-*
    /opt/alt
    /etc/MagicMail
    /etc/eximstats.conf
    /etc/exim.conf
    /etc/exim.conf.local
    /etc/exim.conf.localopts
    /etc/proftpd.conf
    /etc/pure-ftpd.conf
    /etc/dovecot
    /etc/mailman
    /etc/mail
    /var/named/cache
    /var/named/chroot
)

CPANEL_HOME_DIRS=(
    /home/virtfs
    /home/cpeasyapache
    /home/cpanelphppgadmin
    /home/cpanelphpmyadmin
    /home/cpanelroundcube
    /home/cpanelhorde
    /home/cpanelanalytics
    /home/cpanelsolr
    /home/cpanelconnecttrack
    /home/mailman
)

CPANEL_LOG_PATHS=(
    /var/log/cpanel
    /var/log/cpanel-install.log
    /var/log/cpanel-install-selections.txt
    /var/log/cpupdate.log
    /var/log/chkservd.log
    /var/log/cphulkd_errors.log
    /var/log/tailwatchd_log
    /var/log/queueprocd.log
    /var/log/exim_mainlog*
    /var/log/exim_paniclog*
    /var/log/exim_rejectlog*
    /var/log/maillog*
    /var/log/php-fpm
    /var/log/apache2
    /var/log/httpd
    /var/log/ea4_build.log
    /var/log/easy
)

CPANEL_CRON_PATHS=(
    /etc/cron.d/cpanel
    /etc/cron.d/cpanel_tzsetup.initial_install
    /etc/cron.d/cpbandwd
    /etc/cron.d/cpanel_newperl_update
    /etc/cron.d/cpanel_newkernel_update
    /etc/cron.d/cpanel-dcv
    /etc/cron.d/cpanel-hooks
    /etc/cron.hourly/cpanel-hourly
    /etc/cron.daily/cpanel-backups
    /etc/cron.daily/cpanel-bwdata
    /etc/cron.weekly/cpbackup
)

CPANEL_REPOS=(
    /etc/yum.repos.d/cpanel.repo
    /etc/yum.repos.d/cpanel-plugins.repo
    /etc/yum.repos.d/EA4.repo
    /etc/yum.repos.d/imunify*.repo
    /etc/yum.repos.d/mysql-cpanel.repo
    /etc/yum.repos.d/MariaDB*.repo
    /etc/yum.repos.d/cl-*.repo
)

# ------------------------------------------------------------------------------
remove_cpanel_directories() {
    log_info "Removing cPanel application directories"
    for d in "${CPANEL_DIRS[@]}"; do
        # Expand globs
        for expanded in ${d}; do
            remove_path "${expanded}"
        done
    done

    if [[ $KEEP_HOME -eq 1 ]]; then
        log_info "Skipping /home sub-directories (--keep-home)"
    else
        for d in "${CPANEL_HOME_DIRS[@]}"; do
            remove_path "${d}"
        done
    fi

    if [[ $KEEP_MYSQL -eq 0 && -d /var/lib/mysql ]]; then
        log_warn "Removing /var/lib/mysql (MySQL data)"
        remove_path "/var/lib/mysql"
        remove_path "/var/lib/mysql-files"
        remove_path "/etc/my.cnf"
        remove_path "/etc/my.cnf.d"
    fi
}

remove_cpanel_configs() {
    log_info "Removing cPanel configuration files"
    local cfgs=(
        /etc/wwwacct.conf
        /etc/exim.conf
        /etc/exim_outgoing.conf
        /etc/cpupdate.conf
        /etc/clamd.d/scan.conf
        /etc/proftpd/cpanel.conf
        /etc/my.cnf.cpaneldb
        /etc/named.conf.cpanel
        /etc/chkserv.d
        /etc/rndc.conf
        /etc/rndc.key
    )
    for f in "${cfgs[@]}"; do
        remove_path "${f}"
    done

    # Remove cPanel-added bash profile fragments
    remove_path "/etc/profile.d/cpanel.sh"
    remove_path "/etc/profile.d/cpanel_scl.sh"
    remove_path "/etc/profile.d/ea-php.sh"

    # Remove systemd drop-ins created by cPanel
    remove_path "/etc/systemd/system/cpanel.service"
    remove_path "/etc/systemd/system/cpanel.service.d"
    safe_cmd "systemctl daemon-reload"
}

remove_cpanel_logs() {
    log_info "Removing cPanel log files"
    for p in "${CPANEL_LOG_PATHS[@]}"; do
        for expanded in ${p}; do
            remove_path "${expanded}"
        done
    done
}

remove_cpanel_cron() {
    log_info "Removing cPanel cron jobs"
    for p in "${CPANEL_CRON_PATHS[@]}"; do
        for expanded in ${p}; do
            remove_path "${expanded}"
        done
    done

    # Strip cPanel entries from root crontab
    if [[ -f /var/spool/cron/root ]]; then
        if grep -qE '(cpanel|cpbackup|eximstats|/scripts/)' /var/spool/cron/root 2>/dev/null; then
            log_info "Cleaning cPanel entries from root crontab"
            safe_cmd "cp /var/spool/cron/root /var/spool/cron/root.preuninstall.bak"
            if [[ $DRY_RUN -eq 0 ]]; then
                sed -i.bak -E '/(cpanel|cpbackup|eximstats|\/scripts\/)/d' /var/spool/cron/root || true
            fi
        fi
    fi
}

remove_cpanel_repos() {
    log_info "Removing cPanel yum/dnf repositories"
    for p in "${CPANEL_REPOS[@]}"; do
        for expanded in ${p}; do
            remove_path "${expanded}"
        done
    done
    safe_cmd "${PKG_MGR:-dnf} clean all"
}

# ------------------------------------------------------------------------------
# System file restoration
# ------------------------------------------------------------------------------
restore_hosts_file() {
    # cPanel rewrites /etc/hosts; restore a minimal correct one.
    local host
    host="$(hostname 2>/dev/null || echo localhost)"
    if [[ -f /etc/hosts.bak.cpanel-uninstall ]]; then
        log_info "Hosts file backup already exists, skipping"
    elif [[ -f /etc/hosts ]]; then
        safe_cmd "cp /etc/hosts /etc/hosts.bak.cpanel-uninstall"
    fi

    if [[ $DRY_RUN -eq 0 ]]; then
        cat > /etc/hosts <<EOF
# Restored by cpanel-uninstaller on $(date)
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 ${host}
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6 ${host}
EOF
    else
        log_info "[DRY-RUN] rewrite /etc/hosts"
    fi
}

restore_resolv_conf() {
    # Leave NetworkManager-managed resolv.conf alone; only fix if empty.
    if [[ ! -s /etc/resolv.conf ]]; then
        log_info "Empty /etc/resolv.conf; writing fallback DNS"
        if [[ $DRY_RUN -eq 0 ]]; then
            cat > /etc/resolv.conf <<EOF
# Fallback nameservers written by cpanel-uninstaller
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
        fi
    fi
}

restore_sshd_config() {
    # cPanel drops an override in /etc/ssh/sshd_config.d/ that forces
    # key-only authentication. Leaving it in place after the uninstall
    # locks out anyone who logs in by password.
    #
    # This function:
    #   1. Removes cPanel SSH drop-in files.
    #   2. Strips any cPanel-era AuthenticationMethods lines from the main
    #      sshd_config.
    #   3. Ensures PasswordAuthentication / UsePAM are enabled.
    #   4. Enables and restarts the sshd service.
    local sshd_cfg="/etc/ssh/sshd_config"
    local dropin_dir="/etc/ssh/sshd_config.d"
    local backup="${sshd_cfg}.cpanel-uninstaller.bak"

    # 1. Remove cPanel drop-ins (40-cpanel.conf, 50-cpanel.conf, etc.)
    if [[ -d "${dropin_dir}" ]]; then
        local f
        for f in "${dropin_dir}"/*cpanel*.conf "${dropin_dir}"/*cpnl*.conf; do
            if [[ -e "${f}" ]]; then
                log_info "Removing cPanel SSH drop-in: ${f}"
                remove_path "${f}"
            fi
        done
    fi

    # 2 & 3. Normalise the main sshd_config so password login works.
    if [[ -f "${sshd_cfg}" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[DRY-RUN] would normalise ${sshd_cfg} (PasswordAuthentication yes, drop AuthenticationMethods)"
        else
            cp -a "${sshd_cfg}" "${backup}"
            log_info "sshd_config backup: ${backup}"

            # Force PasswordAuthentication yes (covers commented + uncommented lines).
            if grep -qE '^[[:space:]]*#?[[:space:]]*PasswordAuthentication' "${sshd_cfg}"; then
                sed -i 's|^[[:space:]]*#\?[[:space:]]*PasswordAuthentication.*|PasswordAuthentication yes|' "${sshd_cfg}"
            else
                printf '\nPasswordAuthentication yes\n' >> "${sshd_cfg}"
            fi

            # Ensure PAM is used so passwd / shadow are consulted.
            if grep -qE '^[[:space:]]*#?[[:space:]]*UsePAM' "${sshd_cfg}"; then
                sed -i 's|^[[:space:]]*#\?[[:space:]]*UsePAM.*|UsePAM yes|' "${sshd_cfg}"
            else
                printf 'UsePAM yes\n' >> "${sshd_cfg}"
            fi

            # Keep key auth available (do not break existing key-only users).
            if grep -qE '^[[:space:]]*#?[[:space:]]*PubkeyAuthentication' "${sshd_cfg}"; then
                sed -i 's|^[[:space:]]*#\?[[:space:]]*PubkeyAuthentication.*|PubkeyAuthentication yes|' "${sshd_cfg}"
            fi

            # Drop any AuthenticationMethods line (cPanel sets this to publickey).
            sed -i '/^[[:space:]]*AuthenticationMethods[[:space:]]/d' "${sshd_cfg}"

            # Validate. If invalid, restore backup rather than leave a
            # broken config on disk.
            if ! sshd -t 2>/dev/null; then
                log_error "Rewritten sshd_config failed validation; restoring backup"
                cp -a "${backup}" "${sshd_cfg}"
            fi
        fi
    fi

    # 4. Enable and (re)start sshd.
    safe_cmd "systemctl enable sshd --now || true"
    safe_cmd "systemctl restart sshd || true"

    # Report effective state in the log for auditability.
    if [[ $DRY_RUN -eq 0 ]]; then
        log_info "Effective sshd auth config:"
        sshd -T 2>/dev/null \
            | grep -iE '^(passwordauthentication|pubkeyauthentication|authenticationmethods|usepam|permitrootlogin) ' \
            | while read -r line; do log_info "  ${line}"; done || true
    fi
}

restore_network_scripts() {
    # Make sure NetworkManager or network service is enabled
    if systemctl list-unit-files NetworkManager.service &>/dev/null; then
        safe_cmd "systemctl enable --now NetworkManager || true"
    fi
}

remove_cpanel_profile_scripts() {
    # Note: bash's default glob expansion leaves the literal pattern in
    # place when nothing matches. Using `if [[ -e ]]; then ...; fi`
    # (instead of `[[ -e ]] && ...`) returns 0 in that case, so a missing
    # glob does not propagate a failing exit code to the caller under
    # `set -e`.
    local f
    for f in /etc/profile.d/cpanel*.sh /etc/profile.d/ea-*.sh; do
        if [[ -e "${f}" ]]; then
            remove_path "${f}"
        fi
    done
    return 0
}
