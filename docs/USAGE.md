# Detailed Usage Guide

This document is the exhaustive reference for `uninstall-cpanel.sh`. If you
only need a quick start, see [README.md](../README.md) at the repo root.

## 1. Preparing the server

### 1.1 Take a verified backup

The script creates its own safety backup, but that is **not** a substitute
for your production backups. Before running this script:

- Back up all customer data (`/home`, `/var/lib/mysql`, mail, `/var/named`).
- Export a list of cPanel accounts:

  ```bash
  /scripts/mkacctconf   # writes /var/cpanel/users
  ls /var/cpanel/users  # one file per account
  ```

- If possible, take a full VM / block-level snapshot.
- Store the backup **off the server**.

### 1.2 Run in tmux or screen

An SSH disconnection during uninstall can leave the system in a
half-migrated state. Always:

```bash
sudo dnf install -y tmux       # or screen
tmux new -s uninstall
sudo ./uninstall-cpanel.sh
# Ctrl-b d  to detach
# tmux attach -t uninstall   to reattach
```

### 1.3 Pre-flight check

```bash
sudo ./scripts/pre-check.sh
```

Exits 0 if the system is ready. Warns about:

- Wrong OS
- Low disk space
- Missing backup path
- Live SSH session (so you know to use tmux)

---

## 2. Command-line reference

```
Usage: sudo ./uninstall-cpanel.sh [OPTIONS]

Options:
  -f, --force          Skip confirmation prompts (DANGEROUS)
  -n, --dry-run        Print actions but do not execute
  -k, --keep-data      Shortcut for --keep-home --keep-mysql
      --keep-home      Preserve /home contents
      --keep-mysql     Preserve /var/lib/mysql data
      --skip-backup    Do not create a pre-uninstall backup
  -v, --verbose        Verbose logging
  -h, --help           Show help and exit
      --version        Show version
```

### 2.1 Common invocations

| Scenario                                 | Command                                           |
|------------------------------------------|---------------------------------------------------|
| First-time run, interactive              | `sudo ./uninstall-cpanel.sh`                      |
| CI / automation                          | `sudo ./uninstall-cpanel.sh -f -k --skip-backup`  |
| Dry-run preview                          | `sudo ./uninstall-cpanel.sh -n -v`                |
| Keep customer data for reinstall         | `sudo ./uninstall-cpanel.sh --keep-data`          |
| Keep only MySQL databases                | `sudo ./uninstall-cpanel.sh --keep-mysql`         |

---

## 3. What gets removed

### 3.1 Services stopped & disabled

**cPanel core:** `cpanel`, `cpsrvd`, `cphulkd`, `cpdavd`, `cpanel-ccs`,
`cpanellogd`, `queueprocd`, `tailwatchd`, `chkservd`, `cpgreylistd`,
`cpanel-dovecot-solr`.

**Web stack:** `httpd`, `apache2`, `nginx`, `apache_php_fpm`,
`ea-apache24`, `ea-tomcat85`, `ea-tomcat9`.

**Mail:** `exim`, `dovecot`, `mailman`, `mailscanner`, `spamassassin`,
`cpanel-clamd`.

**Database** *(unless `--keep-mysql`)*: `mysqld`, `mariadb`, `postgresql`.

**DNS:** `named`, `named-chroot`, `nsd`, `pdns`.

**FTP:** `pure-ftpd`, `proftpd`, `vsftpd`.

### 3.2 RPM packages removed

- `cpanel-*` (all)
- `ea-*`     (EasyApache 4 stack)
- `alt-*`    (CloudLinux / alt-php compatibility)
- `MariaDB-*`, `mysql-cpanel*`, `Percona-*` (only if `--keep-mysql` not set)
- `cpanel-perl*`, `cpanel-php*`

### 3.3 Directories deleted

| Path                            | Notes                                        |
|---------------------------------|----------------------------------------------|
| `/usr/local/cpanel`             | Main cPanel installation                     |
| `/var/cpanel`                   | cPanel runtime state                         |
| `/etc/cpanel`                   | System-wide cPanel config                    |
| `/scripts`                      | cPanel admin scripts                         |
| `/usr/local/apache`             | Legacy Apache path                           |
| `/opt/cpanel`, `/opt/ea-*`, `/opt/alt` | PHP / addon packages                  |
| `/home/virtfs`, `/home/cpeasyapache`, `/home/cpanel*`  | cPanel sub-accounts (unless `--keep-home`) |
| `/var/lib/mysql`                | *Only if `--keep-mysql` not passed*          |
| `/etc/exim*`, `/etc/dovecot`, `/etc/proftpd`, `/etc/pure-ftpd` | Mail/FTP configs         |
| `/var/log/cpanel*`, `/var/log/exim*`, `/var/log/maillog*`, `/var/log/httpd` | Logs     |

### 3.4 Cron jobs removed

All of `/etc/cron.d/cpanel*`, plus cPanel entries removed from
`/var/spool/cron/root` (a `.preuninstall.bak` is left next to it).

### 3.5 Users / groups removed

`cpanel`, `cpanellogin`, `cpanelphpmyadmin`, `cpanelphppgadmin`,
`cpanelroundcube`, `cpanelhorde`, `cpanelanalytics`, `cpanelsolr`, `cpses`,
`cpaneleximscanner`, `cpanelrrdtool`, `cphulkd`, `cpanel-ccs`, `dovecot`,
`dovenull`, `mailman`, `mailnull`, `nobody-cpanel`, `sfmail`.

Regular accounts (UID ≥ 1000) found in `/var/cpanel/users` are *removed as
users* but their home directories are preserved by default. Pass
`--keep-home` to also skip the `userdel` step for those accounts.

### 3.6 Repositories removed

- `/etc/yum.repos.d/cpanel.repo`
- `/etc/yum.repos.d/cpanel-plugins.repo`
- `/etc/yum.repos.d/EA4.repo`
- `/etc/yum.repos.d/imunify*.repo`
- `/etc/yum.repos.d/mysql-cpanel.repo`
- `/etc/yum.repos.d/MariaDB*.repo` (if `--keep-mysql` not set)

### 3.7 Firewall changes

- CSF/LFD fully removed (runs vendor's `uninstall.sh` if present).
- `firewalld` re-enabled with default `public` zone and `ssh` + `http` +
  `https` services opened.
- `iptables` rules flushed only if CSF chains are still loaded.

---

## 4. What stays intact

The following are **explicitly preserved**:

- `root` user, sudo accounts, regular Linux users
- `sshd` (re-enabled at end of run)
- `dnf` / `yum` and AppStream / BaseOS repos
- Kernel, GRUB, systemd, SELinux, NetworkManager
- Interface configs under `/etc/sysconfig/network-scripts/`
- `/etc/fstab`, `/etc/hostname`
- `/home/<real-user>` (cPanel system homes only are touched)
- MySQL databases when `--keep-mysql` is used

---

## 5. Logs and backups

### 5.1 Log file

Every run writes to:

```
/var/log/cpanel-uninstaller/uninstall-YYYYMMDD-HHMMSS.log
```

The log is also mirrored to stdout/stderr via `tee`. `chmod 600` by default.

### 5.2 Backup

Stored under:

```
/root/cpanel-uninstall-backup-YYYYMMDD-HHMMSS/
/root/cpanel-uninstall-backup-YYYYMMDD-HHMMSS.tar.gz
```

Contents:

- Copies (with full path) of `/etc/passwd`, `/etc/shadow`, `/etc/group`,
  `/etc/sudoers`, `/etc/hosts`, `/etc/resolv.conf`, `/etc/fstab`,
  `/etc/ssh/`, `/etc/yum.repos.d/`, `/etc/cron.d/`, `/var/spool/cron/`,
  `/etc/my.cnf*`, `/etc/firewalld/`, `/etc/csf/`.
- `rpm-before.txt`   — full pre-uninstall package list.
- `services-before.txt` — service unit files & their enabled state.
- `mysql-schema.sql` — MySQL schema dump (only if an unlocked root login
  is possible).

### 5.3 Rollback

This script does **not** provide automatic rollback. The cleanest way to
"undo" is to reinstall cPanel from scratch (see
[REINSTALL.md](REINSTALL.md)) and restore customer data from your own
backup.

Configuration files in the backup directory can be used to reference
previous settings but should not be blindly `cp`-ed back after a
reinstall.

---

## 6. Post-uninstall reboot

After the script finishes:

```bash
sudo ./scripts/post-verify.sh      # optional re-run
sudo systemctl reboot
```

The reboot clears kernel modules loaded by CSF, cPanel's `chkservd`
supervisor, and any zombie `tailwatchd` children.

After the reboot you should have a clean AlmaLinux 9 box with SSH,
`firewalld`, and `dnf` working normally.

---

## 7. Example end-to-end session

```text
$ sudo ./scripts/pre-check.sh
[ OK ] running as root
[ OK ] OS: AlmaLinux release 9.3 (Shamrock Pampas Cat)
[ OK ] cPanel detected (version: 110.0.20)
[ OK ] free space on /root: 12408 MB
All checks passed. Safe to run uninstall-cpanel.sh

$ sudo ./uninstall-cpanel.sh
================================================================================
       cPanel / WHM Complete Uninstaller for AlmaLinux 9  v1.0.0
================================================================================
Type exactly 'REMOVE CPANEL' to proceed…
> REMOVE CPANEL
Do you have a verified backup of all important data? (yes/NO): yes
…
PHASE 1/9  Pre-flight checks
PHASE 2/9  Creating safety backup
PHASE 3/9  Stopping cPanel services
…
================================================================================
                      cPanel / WHM Uninstall Complete
================================================================================
  Duration        : 413s
  Log file        : /var/log/cpanel-uninstaller/uninstall-20260414-142011.log
  Backup location : /root/cpanel-uninstall-backup-20260414-142011

Next Steps
  1. Reboot the server:                sudo systemctl reboot
  2. Verify SSH / network work after reboot
  3. To reinstall cPanel fresh:
       cd /home && curl -o latest -L https://securedownloads.cpanel.net/latest
       sh latest

  See docs/REINSTALL.md for a full fresh-install guide.
================================================================================
```
