#!/usr/bin/env bash
# lib/users.sh - remove cPanel-specific system users

# System users created by cPanel.  DO NOT touch root, admin sudo users, or
# regular Linux accounts (UID < 1000 and > SYSTEM_UID_MIN boundary handled
# implicitly because we list names explicitly).
CPANEL_SYSTEM_USERS=(
    cpanel
    cpanellogin
    cpanelphpmyadmin
    cpanelphppgadmin
    cpanelroundcube
    cpanelhorde
    cpanelconnecttrack
    cpanelcabcache
    cpanelanalytics
    cpanelsolr
    cpses
    cpaneleximscanner
    cpanelrrdtool
    cphulkd
    cpanel-ccs
    dovecot
    dovenull
    mailman
    mailnull
    nobody-cpanel
    sfmail
)

CPANEL_SYSTEM_GROUPS=(
    cpanel
    cpanelphpmyadmin
    cpanelphppgadmin
    cpanelroundcube
    cpanelhorde
    cpanelanalytics
    cpanelsolr
    cpses
    cphulkd
    mailman
    mailnull
    nobody-cpanel
)

_user_exists()  { id "$1" &>/dev/null; }
_group_exists() { getent group "$1" &>/dev/null; }

# We never delete /home/<user> because it may contain real customer data.
# Use --force-home if the user really wants to nuke home dirs.
remove_cpanel_users() {
    for u in "${CPANEL_SYSTEM_USERS[@]}"; do
        if _user_exists "${u}"; then
            log_info "Removing user: ${u}"
            safe_cmd "userdel '${u}' 2>/dev/null || true"
        else
            log_debug "User not present: ${u}"
        fi
    done

    for g in "${CPANEL_SYSTEM_GROUPS[@]}"; do
        if _group_exists "${g}"; then
            log_info "Removing group: ${g}"
            safe_cmd "groupdel '${g}' 2>/dev/null || true"
        else
            log_debug "Group not present: ${g}"
        fi
    done

    # Remove cPanel-managed reseller users listed in /var/cpanel/users
    if [[ -d /var/cpanel/users && $KEEP_HOME -eq 0 ]]; then
        log_info "Removing cPanel-managed account system users"
        local account
        for user_file in /var/cpanel/users/*; do
            [[ -e "${user_file}" ]] || continue
            account=$(basename "${user_file}")
            if _user_exists "${account}" && [[ $(id -u "${account}") -ge 500 ]]; then
                # Preserve home by default unless --force supplied with --keep-home=0
                log_info "Deleting cPanel account user: ${account} (home preserved)"
                safe_cmd "userdel '${account}' 2>/dev/null || true"
            fi
        done
    elif [[ $KEEP_HOME -eq 1 ]]; then
        log_info "Skipping cPanel account users (--keep-home)"
    fi
}
