#!/usr/bin/env bash
# scripts/post-verify.sh
# Verifies the uninstall left the system in a consistent, bootable state.
# Returns 0 on success or warnings-only, 1 if any hard failure.

set -Eeuo pipefail

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; RST=$'\033[0m'

fail=0
warn=0
ok()    { printf '%b[ OK ]%b %s\n' "${GRN}" "${RST}" "$*"; }
warn_() { printf '%b[WARN]%b %s\n' "${YLW}" "${RST}" "$*"; warn=$((warn+1)); }
err()   { printf '%b[FAIL]%b %s\n' "${RED}" "${RST}" "$*"; fail=$((fail+1)); }

echo "==== cpanel-uninstaller post-verification ===="

# 1. cPanel directories gone
for p in /usr/local/cpanel /var/cpanel /etc/cpanel /scripts; do
    if [[ -e "${p}" ]]; then warn_ "still exists: ${p}"
    else ok "removed: ${p}"; fi
done

# 2. cPanel packages gone
count=$(rpm -qa 2>/dev/null | grep -cE '^(cpanel|ea-|MariaDB-|alt-)' || true)
if [[ ${count} -eq 0 ]]; then
    ok "no cPanel/EA4/alt packages remain"
else
    warn_ "${count} cPanel-related package(s) remain (rpm -qa | grep -E '^(cpanel|ea-)')"
fi

# 3. Services
for svc in cpanel cpsrvd cphulkd exim dovecot; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        err "service still running: ${svc}"
    else
        ok "service stopped: ${svc}"
    fi
done

# 4. SSH must still work
if systemctl is-enabled --quiet sshd; then
    ok "sshd enabled"
else
    err "sshd is NOT enabled – DO NOT REBOOT until fixed: systemctl enable sshd"
fi
if ss -tln 2>/dev/null | grep -q ':22 '; then
    ok "sshd listening on :22"
else
    err "sshd not listening; don't close your session"
fi

# 5. Network reachable (default route)
if ip route show default &>/dev/null; then
    ok "default route present: $(ip route show default | head -1)"
else
    err "no default route; network may be broken"
fi

# 6. DNS
if getent hosts cpanel.net &>/dev/null; then
    ok "DNS resolution works"
else
    warn_ "DNS resolution failed; check /etc/resolv.conf"
fi

# 7. Package manager functional
if dnf --version &>/dev/null || yum --version &>/dev/null; then
    ok "package manager works"
else
    err "package manager broken"
fi

# 8. SELinux status
sel=$(getenforce 2>/dev/null || echo "unknown")
ok "SELinux: ${sel}"

# 9. Root account
if id root &>/dev/null; then
    ok "root account intact"
else
    err "root account missing (catastrophic)"
fi

# 10. Disk space
free_pct=$(df -P / | awk 'NR==2{print $5}' | tr -d %)
if [[ ${free_pct:-100} -lt 90 ]]; then
    ok "root fs ${free_pct}% used"
else
    warn_ "root fs ${free_pct}% used; clean up if possible"
fi

echo "----------------------------------------------"
if [[ ${fail} -gt 0 ]]; then
    printf '%b%d hard failure(s) – DO NOT REBOOT until fixed%b\n' "${RED}" "${fail}" "${RST}"
    exit 1
fi
if [[ ${warn} -gt 0 ]]; then
    printf '%b%d warning(s); system is bootable but review above%b\n' "${YLW}" "${warn}" "${RST}"
    exit 0
fi
printf '%bAll checks passed. Safe to reboot.%b\n' "${GRN}" "${RST}"
exit 0
