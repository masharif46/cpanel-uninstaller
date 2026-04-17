# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-04-17

### Added
- Initial public release.
- Main script `uninstall-cpanel.sh` with 9-phase uninstall.
- Library modules: `common.sh`, `services.sh`, `packages.sh`, `users.sh`,
  `cleanup.sh`, `firewall.sh`.
- Helper scripts: `pre-check.sh`, `backup.sh`, `post-verify.sh`.
- Documentation: `README.md`, `USAGE.md`, `REINSTALL.md`,
  `TROUBLESHOOTING.md`, `FAQ.md`, `CONTRIBUTING.md`.
- Dry-run mode (`--dry-run`).
- `--keep-home` and `--keep-mysql` flags to preserve customer data.
- Automatic backup to `/root/cpanel-uninstall-backup-<timestamp>/`.
- Prominent "STOP — Read before running" section at the top of `README.md`
  with a pre-flight checklist and KVM / rescue-mode warning.
- `README.md` troubleshooting entry: "Locked out of SSH after uninstall"
  with the exact fix commands.
- SSH auth restore in Phase 8: removes cPanel SSH drop-in files, re-enables
  `PasswordAuthentication`, `UsePAM`, `PubkeyAuthentication`, strips any
  `AuthenticationMethods` directive, validates with `sshd -t` before
  restarting (rolls back on failure), and logs the effective auth config.
- SSH lockout warning in the script banner and a verification step in the
  post-uninstall "Next Steps" output.
- ShellCheck GitHub Actions workflow.
- MIT license.

### Known issues
- AlmaLinux 8 and CloudLinux not yet supported.
- No automated test suite yet.
- `--skip-backup` does not yet suppress the `pre-uninstall` backup made
  during `phase_backup` — pass `--skip-backup` explicitly to disable.
