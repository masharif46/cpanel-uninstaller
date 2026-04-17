#!/usr/bin/env bash
# lib/packages.sh - remove cPanel RPM packages safely

# Detect package manager (AlmaLinux 9 ships dnf; fall back to yum for safety)
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    PKG_MGR=""
fi

_remove_rpms() {
    local title="$1"; shift
    local pattern="$1"; shift
    local pkgs
    pkgs=$(rpm -qa 2>/dev/null | grep -E "${pattern}" || true)
    if [[ -z "${pkgs}" ]]; then
        log_debug "${title}: no matching packages"
        return 0
    fi
    log_info "${title}: removing $(echo "${pkgs}" | wc -l) package(s)"
    # Use rpm -e with --nodeps because cPanel packages have thousands of
    # interdependencies; we're removing the whole stack anyway.
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[DRY-RUN] rpm -e --nodeps --allmatches '${pkg}'"
            continue
        fi
        log_debug "rpm -e ${pkg}"
        if rpm -e --nodeps --allmatches "${pkg}" 2>/dev/null; then
            continue
        fi
        # Scriptlet (pre/postun) failed — retry skipping scripts and triggers.
        # Common with cPanel plugin packages (socialbee, xovi, etc.) whose
        # license-removal scripts exit non-zero when the service is gone.
        log_debug "Retrying ${pkg} with --noscripts --notriggers"
        if rpm -e --nodeps --allmatches --noscripts --notriggers "${pkg}" 2>/dev/null; then
            continue
        fi
        # Last resort: drop the package from the RPM DB only. Files are
        # cleaned in Phase 6 anyway, so leaving them briefly is safe and
        # stops a stuck package from blocking a later reinstall.
        log_debug "Retrying ${pkg} with --justdb"
        if rpm -e --nodeps --allmatches --noscripts --notriggers --justdb "${pkg}" 2>/dev/null; then
            log_warn "Removed ${pkg} from RPM DB only (files will be cleaned in Phase 6)"
        else
            log_warn "Failed to remove ${pkg} (ignored)"
        fi
    done <<< "${pkgs}"
}

remove_cpanel_packages() {
    # Main cpanel-* meta packages
    _remove_rpms "cPanel core" '^(cpanel-|cp-|cpanel$)'
}

remove_ea4_packages() {
    # EasyApache 4 stack: apache, modules, php
    _remove_rpms "EasyApache 4" '^ea-'
    _remove_rpms "alt-* compat"  '^alt-'
}

remove_cpanel_mysql_packages() {
    if [[ $KEEP_MYSQL -eq 1 ]]; then
        log_info "Keeping MySQL/MariaDB packages (--keep-mysql)"
        return 0
    fi
    _remove_rpms "cPanel MySQL/MariaDB"  '^(MariaDB-|mysql-cpanel|Percona-|mariadb-)'
}

remove_cpanel_perl_packages() {
    _remove_rpms "cPanel Perl" '^(cpanel-perl|perl-cpanel)'
}

remove_cpanel_php_packages() {
    _remove_rpms "cPanel PHP" '^(cpanel-php|cpanel-default-php)'
}

# Clean repo-side cache so stale metadata doesn't bite us
clean_pkg_cache() {
    if [[ -z "${PKG_MGR}" ]]; then
        log_warn "No dnf/yum found; skipping cache cleanup"
        return 0
    fi
    safe_cmd "${PKG_MGR} clean all"
    safe_cmd "rm -rf /var/cache/${PKG_MGR}/* /var/cache/dnf/* 2>/dev/null || true"
}

# Rebuild RPM DB after bulk --nodeps removal
rebuild_rpm_db() {
    log_info "Rebuilding RPM database"
    safe_cmd "rpm --rebuilddb"
}
