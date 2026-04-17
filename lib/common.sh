#!/usr/bin/env bash
# lib/common.sh - shared helper functions for the uninstaller
# shellcheck disable=SC2034

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
init_logging() {
    mkdir -p "${LOG_DIR}"
    : > "${LOG_FILE}"
    chmod 600 "${LOG_FILE}"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log_info "cpanel-uninstaller v${SCRIPT_VERSION} starting on $(hostname) at $(date)"
    log_info "Flags: FORCE=${FORCE} DRY_RUN=${DRY_RUN} KEEP_HOME=${KEEP_HOME} KEEP_MYSQL=${KEEP_MYSQL} SKIP_BACKUP=${SKIP_BACKUP}"
}

_ts() { date +'%Y-%m-%d %H:%M:%S'; }

log_info()  { printf '%s %b[INFO]%b  %s\n'  "$(_ts)" "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn()  { printf '%s %b[WARN]%b  %s\n'  "$(_ts)" "${C_YELLOW}" "${C_RESET}" "$*"; }
log_error() { printf '%s %b[ERROR]%b %s\n' "$(_ts)" "${C_RED}"    "${C_RESET}" "$*" >&2; }
log_debug() {
    [[ $VERBOSE -eq 1 ]] && printf '%s %b[DEBUG]%b %s\n' "$(_ts)" "${C_BLUE}" "${C_RESET}" "$*"
    return 0
}
# ------------------------------------------------------------------------------
# Phase progress bar
# ------------------------------------------------------------------------------
_PHASE_COUNTER=0
_PHASE_TOTAL=9

_print_phase_progress() {
    local current=$1
    local total=$2
    local pct=$(( current * 100 / total ))
    local bar_width=50
    local filled=$(( current * bar_width / total ))
    local empty=$(( bar_width - filled ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf '%b  [%s] %3d%%  Phase %d/%d%b\n' \
        "${C_CYAN}" "${bar}" "${pct}" "${current}" "${total}" "${C_RESET}"
}

log_phase() {
    _PHASE_COUNTER=$(( _PHASE_COUNTER + 1 ))
    echo
    _print_phase_progress "${_PHASE_COUNTER}" "${_PHASE_TOTAL}"
    printf '%b==============================================================================%b\n' "${C_CYAN}${C_BOLD}" "${C_RESET}"
    printf '%b%s%b\n' "${C_CYAN}${C_BOLD}" "$*" "${C_RESET}"
    printf '%b==============================================================================%b\n' "${C_CYAN}${C_BOLD}" "${C_RESET}"
}

# ------------------------------------------------------------------------------
# Command execution helpers
# ------------------------------------------------------------------------------
run_cmd() {
    local cmd="$*"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] ${cmd}"
        return 0
    fi
    log_debug "\$ ${cmd}"
    eval "${cmd}"
}

# Run a command but do not abort on failure; useful for best-effort cleanup.
safe_cmd() {
    local cmd="$*"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] ${cmd}"
        return 0
    fi
    log_debug "\$ ${cmd}"
    eval "${cmd}" || log_warn "Command failed (ignored): ${cmd}"
}

# Remove a path if it exists (respects dry-run).
remove_path() {
    local path="$1"
    if [[ -e "${path}" || -L "${path}" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[DRY-RUN] rm -rf ${path}"
        else
            log_debug "Removing ${path}"
            # cPanel sets append-only (chattr +a) on several log files
            # (stats_log, cphulkd_errors.log, error_log, dnsadmin_log, etc.)
            # and immutable (+i) on a few data files (var/cpanel/analytics/
            # system_id). rm returns "Operation not permitted" on those
            # even as root until the attributes are cleared.
            if command -v chattr &>/dev/null && [[ -d "${path}" || -f "${path}" ]]; then
                chattr -R -ia -- "${path}" 2>/dev/null || true
            fi
            rm -rf --one-file-system -- "${path}" || log_warn "Could not remove ${path}"
        fi
    else
        log_debug "Skip (not present): ${path}"
    fi
}

# ------------------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------------------
require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)."
        exit 2
    fi
    log_debug "Running as root OK"
}

require_almalinux_9() {
    local release_file="/etc/almalinux-release"
    if [[ ! -f "${release_file}" ]]; then
        log_error "File ${release_file} not found. This script only supports AlmaLinux 9."
        exit 3
    fi
    if ! grep -qE 'AlmaLinux.*release[[:space:]]+9' "${release_file}"; then
        log_error "Unsupported OS: $(cat "${release_file}")"
        log_error "This script only supports AlmaLinux 9.x"
        exit 3
    fi
    log_info "OS check passed: $(cat "${release_file}")"
}

detect_cpanel_installation() {
    local found=0
    [[ -d /usr/local/cpanel ]] && { log_info "/usr/local/cpanel present"; found=1; }
    [[ -d /var/cpanel ]]       && { log_info "/var/cpanel present"; found=1; }
    if command -v /usr/local/cpanel/cpanel &>/dev/null; then
        local v
        v=$(/usr/local/cpanel/cpanel -V 2>/dev/null || echo "unknown")
        log_info "Detected cPanel version: ${v}"
        found=1
    fi
    if [[ $found -eq 0 ]]; then
        log_warn "No cPanel installation detected. The script will still try to clean any leftovers."
        if [[ $FORCE -ne 1 ]]; then
            read -r -p "Continue anyway? (yes/NO): " reply
            if [[ "${reply,,}" != "yes" ]]; then
                log_error "Aborted by user."
                exit 4
            fi
        fi
    fi
}

check_disk_space() {
    local free_mb
    free_mb=$(df -Pm /root | awk 'NR==2{print $4}')
    if [[ ${free_mb:-0} -lt 1024 && $SKIP_BACKUP -ne 1 ]]; then
        log_warn "Less than 1GB free on /root; backup may fail (found ${free_mb}MB). Use --skip-backup to bypass."
    fi
}

check_network() {
    if ping -c1 -W2 1.1.1.1 &>/dev/null; then
        log_debug "Network reachable"
    else
        log_warn "Network appears unreachable; package removal uses local RPM DB so this is OK."
    fi
}

check_no_cpanel_installer_running() {
    # Running the uninstaller while cPanel's own installer is active causes
    # mid-flight package corruption (e.g. DBI.pm never written) because both
    # processes race over the RPM database and filesystem.
    local installer_patterns=(
        'sh latest'
        'sh /home/latest'
        '/usr/local/cpanel/scripts/updatenow'
        '/usr/local/cpanel/scripts/cpanel_initial_install'
        'cpanel_install'
    )
    local found_pid=""
    local found_cmd=""
    for pat in "${installer_patterns[@]}"; do
        found_pid=$(pgrep -f "${pat}" 2>/dev/null | head -1 || true)
        if [[ -n "${found_pid}" ]]; then
            found_cmd=$(ps -p "${found_pid}" -o args= 2>/dev/null || echo "${pat}")
            break
        fi
    done

    if [[ -n "${found_pid}" ]]; then
        log_error "A cPanel installer/updater process is currently running (PID ${found_pid}):"
        log_error "  ${found_cmd}"
        log_error "Running the uninstaller concurrently will corrupt the RPM database and"
        log_error "leave the system in an unrecoverable mixed state."
        log_error "Kill it first:  kill ${found_pid}  (or:  pkill -f 'sh latest')"
        if [[ $FORCE -eq 1 ]]; then
            log_warn "--force passed; proceeding anyway (DANGEROUS)"
        else
            exit 5
        fi
    else
        log_debug "No cPanel installer process detected"
    fi
}

# ------------------------------------------------------------------------------
# Minimal fallback backup (used when scripts/backup.sh missing)
# ------------------------------------------------------------------------------
create_minimal_backup() {
    local dest="$1"
    run_cmd "mkdir -p '${dest}'"
    run_cmd "chmod 700 '${dest}'"
    local items=(
        /etc/hosts /etc/resolv.conf /etc/fstab
        /etc/ssh /etc/yum.repos.d
        /etc/passwd /etc/shadow /etc/group /etc/gshadow
        /var/spool/cron /etc/cron.d
        /var/cpanel/users /etc/wwwacct.conf
    )
    for item in "${items[@]}"; do
        if [[ -e "${item}" ]]; then
            run_cmd "cp -a --parents '${item}' '${dest}/' 2>/dev/null || true"
        fi
    done
    # Snapshot package list
    run_cmd "rpm -qa | sort > '${dest}/installed-packages-before.txt'"
    run_cmd "systemctl list-unit-files --no-legend > '${dest}/services-before.txt'"
    log_info "Minimal backup stored in ${dest}"
}

# ------------------------------------------------------------------------------
# Post-verification fallback
# ------------------------------------------------------------------------------
run_post_verification() {
    local issues=0

    log_info "Checking that cPanel files are gone..."
    for p in /usr/local/cpanel /var/cpanel /etc/cpanel /scripts; do
        if [[ -e "${p}" ]]; then
            log_warn "Still present: ${p}"
            issues=$((issues+1))
        fi
    done

    log_info "Checking that cPanel packages are gone..."
    local remaining
    remaining=$(rpm -qa 2>/dev/null | grep -Ec '^(cpanel|ea-|cpanel-|alt-|MariaDB-)' || true)
    if [[ ${remaining} -gt 0 ]]; then
        log_warn "${remaining} cPanel-related package(s) remain. Run: rpm -qa | grep -E '^(cpanel|ea-|MariaDB-)'"
        issues=$((issues+1))
    fi

    log_info "Checking that SSH is still enabled..."
    if ! systemctl is-enabled sshd &>/dev/null; then
        log_error "SSH is NOT enabled; please enable it before rebooting: systemctl enable sshd"
        issues=$((issues+1))
    fi

    log_info "Checking that network is functional..."
    if ! ip route get 1.1.1.1 &>/dev/null; then
        log_warn "Default route missing; verify networking before reboot."
        issues=$((issues+1))
    fi

    if [[ ${issues} -eq 0 ]]; then
        log_info "Post-verification passed with no issues."
    else
        log_warn "Post-verification completed with ${issues} issue(s); see warnings above."
    fi
}
