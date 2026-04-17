#!/usr/bin/env bash
#
# cPanel/WHM Complete Uninstaller for AlmaLinux 9
# ================================================
# Safely removes cPanel & WHM from an AlmaLinux 9 server while keeping the
# base operating system intact and usable (SSH, network, yum/dnf all remain
# functional). After running this script the server is ready for a clean
# cPanel reinstall or can continue to be used as a generic LAMP host.
#
# Repository : https://github.com/masharif46/cpanel-uninstaller
# Author     : masharif46 <https://github.com/masharif46>
# License    : MIT
# Version    : 1.0.0
#
# Usage:
#   sudo ./uninstall-cpanel.sh              # interactive
#   sudo ./uninstall-cpanel.sh --force      # no prompts
#   sudo ./uninstall-cpanel.sh --dry-run    # show actions only
#   sudo ./uninstall-cpanel.sh --keep-data  # preserve /home & MySQL data
#
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------
# Globals
# ------------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
HELPERS_DIR="${SCRIPT_DIR}/scripts"

LOG_DIR="/var/log/cpanel-uninstaller"
LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/root/cpanel-uninstall-backup-$(date +%Y%m%d-%H%M%S)"

# Flags (overridable via CLI)
FORCE=0
DRY_RUN=0
KEEP_DATA=0
KEEP_MYSQL=0
KEEP_HOME=0
SKIP_BACKUP=0
VERBOSE=0

# ------------------------------------------------------------------------------
# Colours
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'
    C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_BOLD="" C_RESET=""
fi

# ------------------------------------------------------------------------------
# Source library modules
# ------------------------------------------------------------------------------
for lib in common services packages users cleanup firewall; do
    if [[ -f "${LIB_DIR}/${lib}.sh" ]]; then
        # shellcheck disable=SC1090
        source "${LIB_DIR}/${lib}.sh"
    else
        echo "ERROR: Missing required library: ${LIB_DIR}/${lib}.sh" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
print_banner() {
    cat <<EOF
${C_CYAN}${C_BOLD}
================================================================================
       cPanel / WHM Complete Uninstaller for AlmaLinux 9  v${SCRIPT_VERSION}
================================================================================
${C_RESET}
${C_YELLOW}WARNING:${C_RESET} This script will:
  * Permanently remove all cPanel & WHM software
  * Remove EasyApache 4, Exim, Dovecot, Pure-FTPd, BIND, MariaDB (if cPanel's)
  * Delete /usr/local/cpanel, /var/cpanel, /etc/cpanel, /scripts
  * Delete cPanel users (mailman, cpanel, cpses, cpanelphpmyadmin, etc.)
  * Clean cron jobs, firewall rules, and repository definitions

${C_GREEN}The script will NOT remove:${C_RESET}
  * The root user or regular sudo admins
  * SSH, network, dnf/yum, systemd, selinux
  * Kernel / core OS packages
  * /home contents          (unless --force  given without --keep-data)
  * MySQL databases         (when --keep-mysql is passed)

${C_RED}${C_BOLD}SSH LOCKOUT WARNING:${C_RESET}
  cPanel disables password SSH login and drops
  ${C_BOLD}/etc/ssh/sshd_config.d/*cpanel*.conf${C_RESET} forcing key-only auth.
  This script will re-enable PasswordAuthentication in Phase 8, but you
  should still have one of the following ready BEFORE continuing:
    * A working SSH key in /root/.ssh/authorized_keys (tested), OR
    * KVM / IPMI / VNC / serial console access, OR
    * Hosting-provider rescue-mode access.
  See README.md section ${C_BOLD}"STOP — Read before running"${C_RESET} for the pre-flight
  checklist.

A full backup is taken to: ${C_BOLD}${BACKUP_DIR}${C_RESET}
A detailed log is written to: ${C_BOLD}${LOG_FILE}${C_RESET}
================================================================================
EOF
}

# ------------------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
${C_BOLD}Usage:${C_RESET} sudo ./${SCRIPT_NAME} [OPTIONS]

Options:
  -f, --force          Skip all confirmation prompts (DANGEROUS)
  -n, --dry-run        Print actions but do not execute them (also skips prompt)
  -k, --keep-data      Equivalent to --keep-home --keep-mysql
      --keep-home      Preserve /home directory contents
      --keep-mysql     Preserve /var/lib/mysql databases
      --skip-backup    Do not create pre-uninstall backup
  -v, --verbose        Verbose output
  -h, --help           Show this help and exit
      --version        Show script version

Examples:
  sudo ./${SCRIPT_NAME}
  sudo ./${SCRIPT_NAME} --dry-run
  sudo ./${SCRIPT_NAME} --force --keep-data
  sudo ./${SCRIPT_NAME} -f -k -v  2>&1 | tee uninstall.log

Exit codes:
  0   success
  1   generic error
  2   not running as root
  3   unsupported OS
  4   user aborted
  5   pre-flight check failed

For full documentation see README.md and docs/USAGE.md
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)       FORCE=1 ;;
            -n|--dry-run)     DRY_RUN=1 ;;
            -k|--keep-data)   KEEP_HOME=1; KEEP_MYSQL=1 ;;
            --keep-home)      KEEP_HOME=1 ;;
            --keep-mysql)     KEEP_MYSQL=1 ;;
            --skip-backup)    SKIP_BACKUP=1 ;;
            -v|--verbose)     VERBOSE=1 ;;
            -h|--help)        usage; exit 0 ;;
            --version)        echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"; exit 0 ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

# ------------------------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------------------------
confirm_uninstall() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log_warn "--dry-run supplied: skipping confirmation (no changes will be made)"
        return 0
    fi
    if [[ $FORCE -eq 1 ]]; then
        log_warn "--force supplied: skipping interactive confirmation"
        return 0
    fi

    echo
    echo "${C_RED}${C_BOLD}This action CANNOT be undone.${C_RESET}"
    echo "Type the exact phrase ${C_BOLD}REMOVE CPANEL${C_RESET} (all caps, with space) and press Enter."
    echo "Anything else will abort."
    printf '%bconfirm>%b ' "${C_YELLOW}${C_BOLD}" "${C_RESET}"
    read -r reply
    if [[ "${reply}" != "REMOVE CPANEL" ]]; then
        log_error "Aborted by user (got: '${reply}')."
        exit 4
    fi

    echo
    printf '%bDo you have a verified backup of all important data? (yes/NO):%b ' "${C_YELLOW}${C_BOLD}" "${C_RESET}"
    read -r backup_reply
    if [[ "${backup_reply,,}" != "yes" ]]; then
        log_error "Aborted: take a backup first, then re-run."
        exit 4
    fi
}

# ------------------------------------------------------------------------------
# Phases
# ------------------------------------------------------------------------------
phase_preflight() {
    log_phase "PHASE 1/9  Pre-flight checks"
    require_root
    require_almalinux_9
    check_no_cpanel_installer_running
    detect_cpanel_installation
    check_disk_space
    check_network
    log_info "Pre-flight OK"
}

phase_backup() {
    log_phase "PHASE 2/9  Creating safety backup"
    if [[ $SKIP_BACKUP -eq 1 ]]; then
        log_warn "--skip-backup passed; not creating backup"
        return 0
    fi
    if [[ -x "${HELPERS_DIR}/backup.sh" ]]; then
        run_cmd "${HELPERS_DIR}/backup.sh '${BACKUP_DIR}'"
    else
        create_minimal_backup "${BACKUP_DIR}"
    fi
    log_info "Backup stored at ${BACKUP_DIR}"
}

phase_stop_services() {
    log_phase "PHASE 3/9  Stopping cPanel services"
    stop_cpanel_services
    stop_webstack_services
    stop_mail_services
    stop_db_services
    stop_dns_services
    stop_ftp_services
}

phase_remove_packages() {
    log_phase "PHASE 4/9  Removing packages"
    remove_cpanel_packages
    remove_ea4_packages
    remove_cpanel_mysql_packages
    remove_cpanel_perl_packages
    remove_cpanel_php_packages
    # Rebuild RPM DB immediately after mass --nodeps removal so later phases
    # (and any subsequent fresh cPanel reinstall) see a consistent database.
    rebuild_rpm_db
    clean_pkg_cache
}

phase_remove_users() {
    log_phase "PHASE 5/9  Removing cPanel system users"
    remove_cpanel_users
}

phase_remove_files() {
    log_phase "PHASE 6/9  Removing cPanel files and directories"
    remove_cpanel_directories
    remove_cpanel_configs
    remove_cpanel_logs
    remove_cpanel_cron
    remove_cpanel_repos
}

phase_firewall_cleanup() {
    log_phase "PHASE 7/9  Cleaning firewall rules"
    remove_csf_lfd
    reset_firewalld
    flush_iptables_if_needed
}

phase_system_restore() {
    log_phase "PHASE 8/9  Restoring system defaults"
    restore_hosts_file
    restore_resolv_conf
    restore_sshd_config
    restore_network_scripts
    remove_cpanel_profile_scripts
    rebuild_rpm_db
}

phase_post_verify() {
    log_phase "PHASE 9/9  Post-uninstall verification"
    local _rc=0
    if [[ -x "${HELPERS_DIR}/post-verify.sh" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[DRY-RUN] ${HELPERS_DIR}/post-verify.sh"
        else
            "${HELPERS_DIR}/post-verify.sh" || _rc=$?
        fi
    else
        run_post_verification || _rc=$?
    fi
    # Exit 1 from post-verify means hard failures; the uninstall itself
    # completed, so don't propagate through the ERR trap — just warn loudly.
    if [[ ${_rc} -ne 0 ]]; then
        log_warn "Post-verification exited ${_rc}; review the output above before rebooting."
    fi
}

# ------------------------------------------------------------------------------
# Final report
# ------------------------------------------------------------------------------
print_report() {
    local now elapsed
    now=$(date +%s)
    elapsed=$(( now - START_TS ))
    cat <<EOF

${C_GREEN}${C_BOLD}
================================================================================
                      cPanel / WHM Uninstall Complete
================================================================================${C_RESET}
  Duration        : ${elapsed}s
  Log file        : ${LOG_FILE}
  Backup location : ${BACKUP_DIR}
  OS status       : $(cat /etc/almalinux-release 2>/dev/null || echo 'unknown')
  Kernel          : $(uname -r)

${C_CYAN}${C_BOLD}Next Steps${C_RESET}
  1. ${C_YELLOW}BEFORE you close this console, open a SECOND terminal and verify
     SSH works:${C_RESET}
       ${C_BOLD}ssh root@<server-ip>${C_RESET}
     Password auth has been re-enabled and any cPanel SSH drop-ins removed.
     If login still fails, check: ${C_BOLD}sshd -T | grep -iE 'passwordauth|authmethods'${C_RESET}
  2. Reboot the server:                ${C_BOLD}sudo systemctl reboot${C_RESET}
  3. Verify SSH / network work after reboot (keep console open until confirmed)
  4. To reinstall cPanel fresh:
       ${C_BOLD}cd /home && curl -o latest -L https://securedownloads.cpanel.net/latest${C_RESET}
       ${C_BOLD}sh latest${C_RESET}

  See docs/REINSTALL.md for a full fresh-install guide.
================================================================================
EOF
}

# ------------------------------------------------------------------------------
# Error trap
# ------------------------------------------------------------------------------
on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Script failed at line ${line_no} with exit code ${exit_code}"
    log_error "See ${LOG_FILE} for details."
    log_error "Backup preserved at ${BACKUP_DIR}"
    exit "${exit_code}"
}
trap 'on_error ${LINENO}' ERR

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    START_TS=$(date +%s)

    parse_args "$@"
    init_logging
    print_banner
    confirm_uninstall

    phase_preflight
    phase_backup
    phase_stop_services
    phase_remove_packages
    phase_remove_users
    phase_remove_files
    phase_firewall_cleanup
    phase_system_restore
    phase_post_verify

    print_report
}

main "$@"
