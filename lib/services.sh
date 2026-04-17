#!/usr/bin/env bash
# lib/services.sh - stop and disable cPanel-related services

# ------------------------------------------------------------------------------
# Service groups
# ------------------------------------------------------------------------------
CPANEL_SERVICES=(
    cpanel
    cpanel-dovecot-solr
    cphulkd
    cpdavd
    cpanel-ccs
    cpsrvd
    cpanellogd
    queueprocd
    tailwatchd
    chkservd
    cpgreylistd
    cpanel-php-fpm
    cpanel_php_fpm
)

WEBSTACK_SERVICES=(
    httpd
    apache2
    nginx
    apache_php_fpm
    ea-apache24
    ea-tomcat85
    ea-tomcat9
)

MAIL_SERVICES=(
    exim
    dovecot
    mailman
    cpanel-dovecot-solr
    mailscanner
    spamassassin
    cpanel-clamd
)

DB_SERVICES=(
    mysqld
    mysql
    mariadb
    MariaDB
    postgresql
)

DNS_SERVICES=(
    named
    named-chroot
    nsd
    powerdns
    pdns
)

FTP_SERVICES=(
    pure-ftpd
    proftpd
    vsftpd
)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
_service_stop_disable() {
    local svc="$1"
    if systemctl list-unit-files "${svc}.service" &>/dev/null || \
       systemctl status "${svc}" &>/dev/null; then
        if systemctl is-active --quiet "${svc}"; then
            log_info "Stopping service: ${svc}"
            safe_cmd "systemctl stop '${svc}'"
        fi
        # Only `disable` units that have an [Install] section. Units in
        # state "static", "alias", "linked", "indirect", etc. either can't
        # be disabled or produce "The unit files have no installation
        # config" stderr noise. `is-enabled --quiet` returns 0 for those
        # too, so we check the state string directly.
        local en_state
        en_state=$(systemctl is-enabled "${svc}" 2>/dev/null || true)
        case "${en_state}" in
            enabled|enabled-runtime)
                log_info "Disabling service: ${svc}"
                safe_cmd "systemctl disable '${svc}'"
                ;;
            *)
                log_debug "Service ${svc} state=${en_state:-unknown}; skipping disable"
                ;;
        esac
    else
        log_debug "Service ${svc} not present"
    fi
}

_stop_group() {
    local title="$1"; shift
    local arr=("$@")
    log_info "---- ${title} ----"
    for svc in "${arr[@]}"; do
        _service_stop_disable "${svc}"
    done
}

# ------------------------------------------------------------------------------
# Public entry points
# ------------------------------------------------------------------------------
stop_cpanel_services()   { _stop_group "cPanel core"    "${CPANEL_SERVICES[@]}"; }
stop_webstack_services() { _stop_group "Web stack"      "${WEBSTACK_SERVICES[@]}"; }
stop_mail_services()     { _stop_group "Mail stack"     "${MAIL_SERVICES[@]}"; }

stop_db_services() {
    if [[ $KEEP_MYSQL -eq 1 ]]; then
        log_info "Keeping MySQL/MariaDB running (--keep-mysql)"
        return 0
    fi
    _stop_group "Database" "${DB_SERVICES[@]}"
}

stop_dns_services() { _stop_group "DNS"  "${DNS_SERVICES[@]}"; }
stop_ftp_services() { _stop_group "FTP"  "${FTP_SERVICES[@]}"; }

# ------------------------------------------------------------------------------
# Kill stragglers
# ------------------------------------------------------------------------------
kill_cpanel_processes() {
    log_info "Killing any lingering cPanel processes"
    local patterns=(
        'cpanel'
        'cpsrvd'
        'cpdavd'
        'cphulkd'
        'queueprocd'
        'tailwatchd'
        'chkservd'
        'cpanellogd'
        'cpgreylistd'
        'dovecot'
        'exim'
    )
    for pat in "${patterns[@]}"; do
        if pgrep -f "${pat}" &>/dev/null; then
            safe_cmd "pkill -TERM -f '${pat}' || true"
            sleep 1
            safe_cmd "pkill -KILL -f '${pat}' || true"
        fi
    done
}
