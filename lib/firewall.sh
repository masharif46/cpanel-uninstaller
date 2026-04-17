#!/usr/bin/env bash
# lib/firewall.sh - remove ConfigServer Firewall (CSF/LFD) and reset firewalld

# ------------------------------------------------------------------------------
# CSF / LFD
# ------------------------------------------------------------------------------
remove_csf_lfd() {
    if [[ ! -d /etc/csf && ! -x /usr/sbin/csf ]]; then
        log_debug "CSF/LFD not installed"
        return 0
    fi

    log_info "Disabling CSF/LFD"
    safe_cmd "systemctl stop  csf  2>/dev/null || true"
    safe_cmd "systemctl stop  lfd  2>/dev/null || true"
    safe_cmd "systemctl disable csf 2>/dev/null || true"
    safe_cmd "systemctl disable lfd 2>/dev/null || true"

    if [[ -x /usr/sbin/csf ]]; then
        safe_cmd "/usr/sbin/csf --disable  || true"
        safe_cmd "/usr/sbin/csf -f || true"
    fi

    if [[ -x /etc/csf/uninstall.sh ]]; then
        log_info "Running CSF vendor uninstall script"
        safe_cmd "/etc/csf/uninstall.sh || true"
    fi

    for p in /etc/csf /usr/local/csf /var/lib/csf /etc/chkserv.d/lfd /etc/chkserv.d/csf; do
        remove_path "${p}"
    done
}

# ------------------------------------------------------------------------------
# firewalld reset
# ------------------------------------------------------------------------------
reset_firewalld() {
    if ! systemctl list-unit-files firewalld.service &>/dev/null; then
        log_info "firewalld not installed; nothing to reset"
        return 0
    fi

    log_info "Re-enabling firewalld with default zone = public"
    safe_cmd "systemctl enable --now firewalld"

    # Make sure SSH is allowed BEFORE we drop any custom rules
    safe_cmd "firewall-cmd --zone=public --add-service=ssh --permanent  || true"
    safe_cmd "firewall-cmd --zone=public --add-service=http --permanent || true"
    safe_cmd "firewall-cmd --zone=public --add-service=https --permanent|| true"

    # Remove cPanel-specific permanent rules if any.
    # Use `if [[ -e ]]; then ...; fi` not `[[ -e ]] && ...` so an
    # unmatched glob doesn't propagate a failing exit code under set -e.
    if [[ -d /etc/firewalld ]]; then
        local f
        for f in /etc/firewalld/zones/cpanel*.xml /etc/firewalld/services/cpanel*.xml; do
            if [[ -e "${f}" ]]; then
                remove_path "${f}"
            fi
        done
    fi

    safe_cmd "firewall-cmd --reload || true"
    return 0
}

# ------------------------------------------------------------------------------
# iptables direct flush (only if CSF's iptables rules are still loaded)
# ------------------------------------------------------------------------------
flush_iptables_if_needed() {
    if ! command -v iptables &>/dev/null; then
        return 0
    fi
    # Heuristic: if raw iptables save contains "CSF" chain references, flush.
    if iptables-save 2>/dev/null | grep -qi 'LOCALINPUT\|CSF'; then
        log_warn "CSF iptables chains present; flushing"
        safe_cmd "iptables -F || true"
        safe_cmd "iptables -X || true"
        safe_cmd "iptables -t nat -F    || true"
        safe_cmd "iptables -t nat -X    || true"
        safe_cmd "iptables -t mangle -F || true"
        safe_cmd "iptables -t mangle -X || true"
        safe_cmd "iptables -P INPUT   ACCEPT || true"
        safe_cmd "iptables -P OUTPUT  ACCEPT || true"
        safe_cmd "iptables -P FORWARD ACCEPT || true"
    fi
}
