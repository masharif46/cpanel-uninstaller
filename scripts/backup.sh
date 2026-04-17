#!/usr/bin/env bash
# scripts/backup.sh
# Creates a full safety backup of everything we will touch during uninstall.
# Usage: ./backup.sh /path/to/backup/dir
#
# The backup allows a manual rollback in case something goes wrong.
# It is NOT a substitute for your production backups.

set -Eeuo pipefail

DEST="${1:-/root/cpanel-uninstall-backup-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "${DEST}"
chmod 700 "${DEST}"

echo "[backup] target: ${DEST}"

# -- System identity / release info --------------------------------------------
{
    echo "# cpanel-uninstaller backup"
    echo "# generated: $(date)"
    echo "# host: $(hostname)"
    echo "# kernel: $(uname -a)"
    cat /etc/*release 2>/dev/null
} > "${DEST}/system-info.txt"

# -- Package list before removal ------------------------------------------------
rpm -qa 2>/dev/null | sort > "${DEST}/rpm-before.txt" || true
systemctl list-unit-files --no-legend > "${DEST}/services-before.txt" 2>/dev/null || true
systemctl list-units --type=service --all --no-legend > "${DEST}/services-running-before.txt" 2>/dev/null || true

# -- Configs / credentials ------------------------------------------------------
backup_copy() {
    local src="$1"
    [[ -e "${src}" ]] || return 0
    cp -a --parents "${src}" "${DEST}/" 2>/dev/null || echo "[backup] could not copy ${src}"
}

paths=(
    /etc/hosts /etc/hostname /etc/resolv.conf /etc/fstab
    /etc/ssh  /etc/sysconfig/network-scripts
    /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers /etc/sudoers.d
    /var/spool/cron  /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly
    /etc/wwwacct.conf /etc/exim.conf /etc/exim.conf.local /etc/my.cnf /etc/my.cnf.d
    /etc/named.conf /var/named/chroot/etc
    /var/cpanel/users /var/cpanel/conf /var/cpanel/mainip /var/cpanel/cpanel.config
    /etc/yum.repos.d /etc/dnf
    /etc/selinux/config /etc/sysconfig/selinux
    /etc/firewalld
    /etc/csf
)
for p in "${paths[@]}"; do backup_copy "${p}"; done

# -- MySQL dump (structure only, cheap) -----------------------------------------
if command -v mysqldump &>/dev/null && systemctl is-active --quiet mysqld mariadb 2>/dev/null; then
    echo "[backup] attempting mysqldump --all-databases (no-data, quick)..."
    mysqldump --no-data --all-databases > "${DEST}/mysql-schema.sql" 2>/dev/null || \
        echo "[backup] mysqldump failed (password required?); skip"
fi

# -- Compress --------------------------------------------------------------------
tarball="${DEST%/}.tar.gz"
echo "[backup] compressing to ${tarball}..."
tar -C "$(dirname "${DEST}")" -czf "${tarball}" "$(basename "${DEST}")" 2>/dev/null || \
    echo "[backup] tar compression failed; raw directory kept"

echo "[backup] done. Keep ${DEST}/ and ${tarball} until you are sure everything works."
