# Security Policy

## Reporting a vulnerability

If you discover a security issue in this project, **do not** open a public
GitHub issue.

Instead, open a [private security advisory](https://github.com/masharif46/cpanel-uninstaller/security/advisories/new)
on GitHub with:

1. A description of the vulnerability.
2. Steps to reproduce it (affected version, OS, flags used).
3. Your assessment of impact.

You can expect an initial response within 72 hours and a fix or status
update within 14 days.

## Scope

This project is a system administration tool that **intentionally** runs
destructive commands as root. Reports of "the script can delete files"
are not vulnerabilities — that is the explicit purpose.

Issues we consider in-scope:

- Code paths that delete, overwrite, or modify files **outside** the
  documented allow-list of cPanel paths.
- Code paths that can be triggered to run **before** the confirmation
  prompt or pre-flight checks.
- Command injection via filenames, environment variables, or CLI args.
- Privilege-escalation side-effects (e.g., creating world-writable
  files, `setuid` binaries, or `sudoers` modifications).

## Supported versions

Only the latest minor version receives security fixes.

| Version | Supported |
|---------|-----------|
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |
