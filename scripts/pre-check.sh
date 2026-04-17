#!/usr/bin/env bash
# scripts/pre-check.sh
# Standalone pre-flight checker. Run it BEFORE uninstall-cpanel.sh to see
# whether the system is ready. Exits 0 if healthy, non-zero otherwise.

set -Eeuo pipefail

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; RST=$'\033[0m'

issues=0
ok()   { printf '%b[ OK ]%b %s\n'   "${GRN}" "${RST}" "$*"; }
warn() { printf '%b[WARN]%b %s\n'   "${YLW}" "${RST}" "$*"; issues=$((issues+1)); }
err()  { printf '%b[FAIL]%b %s\n'   "${RED}" "${RST}" "$*"; issues=$((issues+1)); }

echo "==== cpanel-uninstaller pre-flight check ===="

# Root
if [[ ${EUID} -eq 0 ]]; then ok "running as root";
else err "must be run as root (sudo)"; fi

# OS
if [[ -f /etc/almalinux-release ]] && grep -qE 'release[[:space:]]+9' /etc/almalinux-release; then
    ok "OS: $(cat /etc/almalinux-release)"
else
    err "OS is not AlmaLinux 9: $(cat /etc/*release 2>/dev/null | head -1)"
fi

# cPanel detection
if [[ -d /usr/local/cpanel || -d /var/cpanel ]]; then
    cp_ver=$(/usr/local/cpanel/cpanel -V 2>/dev/null || echo unknown)
    ok "cPanel detected (version: ${cp_ver})"
else
    warn "cPanel not detected; uninstall will just clean leftovers"
fi

# Disk space for backup
free_mb=$(df -Pm /root | awk 'NR==2{print $4}')
if [[ ${free_mb:-0} -ge 1024 ]]; then
    ok "free space on /root: ${free_mb} MB"
else
    warn "only ${free_mb} MB free on /root (need 1GB+ for backup)"
fi

# Active SSH session warning
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    warn "you are connected via SSH. If network scripts break, you may be locked out. Consider running in tmux/screen."
fi

# Memory / swap
mem_mb=$(free -m | awk '/^Mem:/{print $2}')
if [[ ${mem_mb} -lt 768 ]]; then
    warn "system has only ${mem_mb}MB RAM (cPanel min is 1GB; uninstall itself is fine)"
fi

# Network
if ping -c1 -W2 1.1.1.1 &>/dev/null; then
    ok "network reachable"
else
    warn "no outbound network; uninstall is offline-safe, but reinstall needs net"
fi

echo "---------------------------------------------"
if [[ ${issues} -eq 0 ]]; then
    printf '%bAll checks passed. Safe to run uninstall-cpanel.sh%b\n' "${GRN}" "${RST}"
    exit 0
elif [[ ${issues} -le 2 ]]; then
    printf '%b%d warning(s); proceed with care%b\n' "${YLW}" "${issues}" "${RST}"
    exit 0
else
    printf '%b%d issue(s) detected; resolve before running uninstall%b\n' "${RED}" "${issues}" "${RST}"
    exit 1
fi
