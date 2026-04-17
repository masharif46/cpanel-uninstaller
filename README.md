# cPanel / WHM Complete Uninstaller for AlmaLinux 9

[![ShellCheck](https://github.com/masharif46/cpanel-uninstaller/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/masharif46/cpanel-uninstaller/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AlmaLinux 9](https://img.shields.io/badge/AlmaLinux-9-blue.svg)](https://almalinux.org/)
[![Bash](https://img.shields.io/badge/language-bash-89e051.svg)](https://www.gnu.org/software/bash/)

> **A safe, production-grade shell utility that completely removes cPanel & WHM
> from an AlmaLinux 9 server _without_ breaking the operating system, so you
> can either keep the box as a plain LAMP host or perform a clean cPanel
> reinstall.**

---

## STOP — Read before running

cPanel silently switches SSH to **key-only authentication** during its own
installation. It drops a file in `/etc/ssh/sshd_config.d/` (e.g.
`40-cpanel.conf`) that sets:

```
PasswordAuthentication no
AuthenticationMethods publickey
```

**If you run this uninstaller without first confirming one of the following,
you WILL be locked out of your server:**

1. You have a working SSH private key already installed in
   `/root/.ssh/authorized_keys` **and** you have tested it from another
   machine, OR
2. You have **KVM / IPMI / VNC / serial console** access through your hosting
   provider, OR
3. You can boot the server into **rescue / single-user mode**.

### Pre-flight checklist (run BEFORE the uninstaller)

```bash
# 1. Check how SSH is configured right now
sshd -T | grep -iE 'passwordauth|pubkeyauth|authenticationmethods|permitroot'

# 2. List any cPanel drop-in files
ls -la /etc/ssh/sshd_config.d/

# 3. Verify you can log in from a second terminal WITHOUT closing the first
#    (test both password and key from another machine)

# 4. Confirm your KVM / console is reachable (hosting provider panel)
```

This script automatically re-enables password authentication during Phase 8.
If you are ever locked out after an uninstall, see
[Troubleshooting → Locked out of SSH after uninstall](#locked-out-of-ssh-after-uninstall).

---

## Table of Contents

- [STOP — Read before running](#stop--read-before-running)
- [Why this script?](#why-this-script)
- [What it does](#what-it-does)
- [What it does NOT touch](#what-it-does-not-touch)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [Command-line options](#command-line-options)
- [Uninstall phases](#uninstall-phases)
- [Safety features](#safety-features)
- [Reinstalling cPanel after uninstall](#reinstalling-cpanel-after-uninstall)
- [Logs & backups](#logs--backups)
- [Project layout](#project-layout)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## Why this script?

cPanel's official documentation states:

> *The only supported way to uninstall cPanel & WHM is to reinstall the
> operating system.*
> — [cPanel docs](https://docs.cpanel.net/)

That is impractical for many real-world scenarios:

- You bought a server with cPanel pre-installed but do not need it.
- Your cPanel trial has expired and you want to keep the VPS as a plain
  Linux box.
- An EasyApache / PHP upgrade broke things and a clean slate (without
  re-installing the OS) is the fastest route back.
- You run CI/CD on dedicated hardware and cannot re-image.

This script removes cPanel, WHM, EasyApache 4, Exim, Dovecot, Pure-FTPd,
BIND, cPanel-managed MariaDB, the cPanel repos, cron jobs, firewall rules,
and system users — while preserving SSH, networking, DNF/YUM, SELinux, the
kernel, your sudoers, and (optionally) your `/home` data and MySQL
databases.

---

## What it does

The uninstaller runs in **nine ordered phases**:

| # | Phase                    | Summary                                                              |
|---|--------------------------|----------------------------------------------------------------------|
| 1 | Pre-flight checks        | Verifies root, AlmaLinux 9, detects cPanel, checks disk/network.    |
| 2 | Backup                   | Tars up configs, crontabs, repo files, DB schemas → `/root/…`.      |
| 3 | Stop services            | `cpanel`, `cpsrvd`, `cphulkd`, `exim`, `dovecot`, `pure-ftpd`, `named`, `mariadb`, `httpd`, etc. |
| 4 | Remove packages          | All `cpanel-*`, `ea-*`, `alt-*`, `MariaDB-*`, `cpanel-perl*`, `cpanel-php*`. |
| 5 | Remove users & groups    | `mailman`, `cpses`, `cpanelphpmyadmin`, `dovecot`, `dovenull`, …    |
| 6 | Remove files & configs   | `/usr/local/cpanel`, `/var/cpanel`, `/etc/cpanel`, `/scripts`, logs, cron, repos. |
| 7 | Firewall cleanup         | Removes CSF/LFD, resets firewalld to a safe default.                |
| 8 | System restore           | Restores `/etc/hosts`, `/etc/resolv.conf`, ensures `sshd` enabled.  |
| 9 | Post-verify              | Sanity-checks that SSH, network, DNS, DNF, root all still work.     |

---

## What it does NOT touch

- **SSH server (`sshd`)** — the uninstaller explicitly re-enables it.
- **Networking** (NetworkManager, interface configs, routing tables).
- **`dnf` / `yum`** and the base AlmaLinux 9 repositories.
- **Kernel, glibc, systemd, SELinux.**
- **Root account, admin/sudo users, normal Linux users.**
- **`/home/<user>` contents** (preserved with `--keep-home`, and even in the
  default run only the cPanel system accounts' home dirs under
  `/home/virtfs`, `/home/cpeasyapache`, etc. are touched).
- **MySQL data** when `--keep-mysql` is passed.

See [docs/USAGE.md](docs/USAGE.md) for the exhaustive list of paths and the
table of what is removed vs. preserved.

---

## Requirements

| Requirement       | Value                                            |
|-------------------|--------------------------------------------------|
| Operating system  | **AlmaLinux 9.x only** (RHEL 9 / Rocky 9 will likely work but are untested) |
| Shell             | Bash 4+                                          |
| Privileges        | `root` (via `sudo`)                              |
| Free disk space   | ~1 GB on `/root` (for the backup)                |
| Recommended       | Run inside `tmux` or `screen` in case network hiccups |

The uninstaller is **offline-safe** — it uses only local `rpm`/`systemctl`
operations, no external package downloads.

---

## Quick start

```bash
# Clone
git clone https://github.com/masharif46/cpanel-uninstaller.git
cd cpanel-uninstaller

# Pre-flight check
sudo ./scripts/pre-check.sh

# Dry-run (shows everything, changes nothing)
sudo ./uninstall-cpanel.sh --dry-run

# Real run
sudo ./uninstall-cpanel.sh
```

You will be asked to type `REMOVE CPANEL` exactly, followed by confirming
that you have a verified backup. The script will not proceed otherwise.

---

## Installation

### Method 1 — clone with git

```bash
cd /root
git clone https://github.com/masharif46/cpanel-uninstaller.git
cd cpanel-uninstaller
chmod +x uninstall-cpanel.sh scripts/*.sh lib/*.sh
```

### Method 2 — curl (no git required)

```bash
cd /root
curl -L https://github.com/masharif46/cpanel-uninstaller/archive/refs/heads/main.tar.gz | tar -xz
mv cpanel-uninstaller-main cpanel-uninstaller
cd cpanel-uninstaller
chmod +x uninstall-cpanel.sh scripts/*.sh lib/*.sh
```

### Method 3 — one-liner via curl

```bash
curl -fsSL https://raw.githubusercontent.com/masharif46/cpanel-uninstaller/main/scripts/install.sh | sudo bash
cd /opt/cpanel-uninstaller
```

### Method 4 — direct download single script

> Not supported. The uninstaller is split into modules (`lib/*.sh`) and
> requires the full repo. See the troubleshooting guide if you must run
> from a restricted environment.

---

## Usage

### Interactive (recommended first time)

```bash
sudo ./uninstall-cpanel.sh
```

### Non-interactive (automation, CI)

```bash
sudo ./uninstall-cpanel.sh --force --keep-data --skip-backup
```

### Dry-run — show every action without doing anything

```bash
sudo ./uninstall-cpanel.sh --dry-run --verbose
```

### Keep customer homes & MySQL data (for migration)

```bash
sudo ./uninstall-cpanel.sh --keep-home --keep-mysql
```

---

## Command-line options

| Flag              | Description                                          |
|-------------------|------------------------------------------------------|
| `-f, --force`     | Skip confirmation prompts (DANGEROUS).               |
| `-n, --dry-run`   | Show actions only; make no changes.                  |
| `-k, --keep-data` | Shortcut for `--keep-home --keep-mysql`.             |
| `--keep-home`     | Preserve `/home` contents.                           |
| `--keep-mysql`    | Preserve `/var/lib/mysql` databases.                 |
| `--skip-backup`   | Do not create a pre-uninstall backup.                |
| `-v, --verbose`   | Verbose (debug-level) logging.                       |
| `-h, --help`      | Show help and exit.                                  |
| `--version`       | Print version.                                       |

### Exit codes

| Code | Meaning                               |
|------|---------------------------------------|
| 0    | Success                               |
| 1    | Generic error                         |
| 2    | Not running as root                   |
| 3    | Unsupported OS (not AlmaLinux 9)      |
| 4    | User aborted at the confirmation step |
| 5    | Pre-flight check failed               |

---

## Uninstall phases

Each phase is isolated in its own library module under `lib/` so you can
audit it, disable a specific phase, or reuse the helpers in your own
tooling.

- `lib/common.sh`     — logging, dry-run, root / OS / disk checks
- `lib/services.sh`   — stop/disable/mask all cPanel services
- `lib/packages.sh`   — bulk `rpm -e --nodeps` of `cpanel-*`, `ea-*`, …
- `lib/users.sh`      — remove cPanel system users & groups
- `lib/cleanup.sh`    — remove directories, configs, logs, cron, repos
- `lib/firewall.sh`   — purge CSF/LFD, reset firewalld

See [docs/USAGE.md](docs/USAGE.md) for the detailed path list.

---

## Safety features

- **Strict mode** — `set -Eeuo pipefail` plus an `ERR` trap that prints the
  failing line number.
- **Pre-flight** — refuses to run on anything that isn't AlmaLinux 9 and
  not as root.
- **Double confirmation** — user must type `REMOVE CPANEL` *and* confirm
  "yes" to having a backup.
- **Automatic backup** — `/etc/hosts`, `/etc/passwd`, `/etc/shadow`,
  `/etc/cron.*`, `/var/cpanel/users`, all `/etc/yum.repos.d/*.repo`, and an
  `rpm -qa` snapshot are tarred into `/root/cpanel-uninstall-backup-<ts>`.
- **Dry-run** — full simulation mode via `--dry-run`.
- **Idempotent** — safe to re-run; missing items are logged and skipped.
- **Non-destructive by default** — `/home` content and databases are
  preserved unless you explicitly opt-out.
- **Post-verification** — `scripts/post-verify.sh` confirms SSH, network,
  DNS, and dnf are still healthy before you reboot.

---

## Reinstalling cPanel after uninstall

After the uninstaller finishes, reboot once and then install a fresh
cPanel:

```bash
sudo systemctl reboot
# … wait for reboot …

cd /home
curl -o latest -L https://securedownloads.cpanel.net/latest
sudo sh latest
```

The install takes ~30-60 minutes. Full instructions including tuning,
`cpanel.config`, licensing, and DNS cluster setup live in
[docs/REINSTALL.md](docs/REINSTALL.md).

---

## Logs & backups

| File / Directory                                         | What it contains                                          |
|----------------------------------------------------------|-----------------------------------------------------------|
| `/var/log/cpanel-uninstaller/uninstall-<ts>.log`         | Full transcript of the run (stdout + stderr).             |
| `/root/cpanel-uninstall-backup-<ts>/`                    | Raw backup directory.                                     |
| `/root/cpanel-uninstall-backup-<ts>.tar.gz`              | Compressed tarball of the same backup.                    |
| `/root/cpanel-uninstall-backup-<ts>/rpm-before.txt`      | Output of `rpm -qa` before removal — useful for audits.   |
| `/root/cpanel-uninstall-backup-<ts>/services-before.txt` | Service states before removal.                            |

Keep the backup for at least a few days until you are sure everything
works. Once comfortable, `rm -rf /root/cpanel-uninstall-backup-*`.

---

## Project layout

```
cpanel-uninstaller/
├── uninstall-cpanel.sh          # Main entry point
├── lib/
│   ├── common.sh                # Shared helpers (logging, checks)
│   ├── services.sh              # Stop/disable services
│   ├── packages.sh              # Remove RPM packages
│   ├── users.sh                 # Remove system users/groups
│   ├── cleanup.sh               # Remove files, cron, repos
│   └── firewall.sh              # CSF/LFD + firewalld cleanup
├── scripts/
│   ├── pre-check.sh             # Pre-flight checker (safe to run anytime)
│   ├── backup.sh                # Standalone backup script
│   └── post-verify.sh           # Post-uninstall sanity check
├── docs/
│   ├── USAGE.md                 # Detailed usage, path inventory
│   ├── REINSTALL.md             # Clean cPanel reinstall instructions
│   ├── TROUBLESHOOTING.md       # Common errors & fixes
│   └── FAQ.md                   # Frequently asked questions
├── .github/
│   └── workflows/
│       └── shellcheck.yml       # CI: ShellCheck all scripts
├── .gitignore
├── LICENSE                       # MIT
└── README.md
```

---

## Troubleshooting

Quick hits (full list in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)):

### Locked out of SSH after uninstall

**Symptom:** `ssh user@host` returns `Permission denied (publickey)` even
though you are typing the correct password.

**Cause:** cPanel dropped an SSH override (usually
`/etc/ssh/sshd_config.d/40-cpanel.conf`) that set
`PasswordAuthentication no` and `AuthenticationMethods publickey`. Older
versions of this uninstaller did not revert that file.

**Fix via KVM / IPMI / rescue console:**

```bash
# 1. Remove any cPanel-era SSH drop-ins
rm -f /etc/ssh/sshd_config.d/*cpanel*.conf

# 2. Re-enable password login in the main config
sed -i 's/^[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^[[:space:]]*UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
sed -i '/^[[:space:]]*AuthenticationMethods/d' /etc/ssh/sshd_config

# 3. Validate and restart
sshd -t && systemctl restart sshd

# 4. Confirm the effective config
sshd -T | grep -iE 'passwordauth|authenticationmethods|permitroot'
```

You should see `passwordauthentication yes` and **no**
`authenticationmethods` line. Keep the console session open until you've
confirmed SSH works from another machine.

### Other common issues

- **`rpm -e` fails with "is needed by …"** — the script uses `--nodeps`
  on purpose; re-run and the dependency chain will resolve.
- **Network down after uninstall** — check `nmcli con show`; the cPanel
  install normally does not touch NetworkManager, but run
  `systemctl enable --now NetworkManager`.
- **Package manager complains about missing repos** — the script deletes
  `cpanel.repo` and `EA4.repo`. Run `dnf clean all`.
- **Still see cPanel processes** — run again with `--force` or check
  `systemctl list-units --type=service | grep -Ei 'cp|exim|dovecot'`.

---

## Contributing

PRs and issues welcome! Please:

1. Run `shellcheck` on every script you touch.
2. Add or update tests in `tests/` (coming soon).
3. Keep the script POSIX-ish where possible (bashisms allowed but
   documented).

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) (if present) for the full
contributor workflow.

---

## Disclaimer

> **This project is not affiliated with, endorsed by, or supported by
> cPanel, L.L.C. or WebPros International.**
>
> It performs destructive, irreversible operations against a production
> control panel. Although every effort has been made to preserve the base
> OS, you run this script **entirely at your own risk**. Always have an
> off-host, tested backup before proceeding. The authors accept no
> liability for data loss, downtime, or any other damage.

---

## License

Released under the [MIT License](LICENSE).
Copyright (c) 2026 [masharif46](https://github.com/masharif46).
