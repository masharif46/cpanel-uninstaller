# Troubleshooting

Solutions to the most common problems you might hit before, during, or
after running `uninstall-cpanel.sh`.

If none of these apply, open a GitHub issue and attach the log file from
`/var/log/cpanel-uninstaller/`.

---

## Before running

### 1. "This script only supports AlmaLinux 9"

The uninstaller checks `/etc/almalinux-release` for the literal string
`AlmaLinux release 9`. If you're on Rocky 9 or RHEL 9 the script refuses
to run as a safety measure.

**Workaround** *(use at your own risk)*:

```bash
# Temporarily spoof /etc/almalinux-release
sudo cp /etc/almalinux-release /etc/almalinux-release.bak 2>/dev/null
echo "AlmaLinux release 9.3 (Shamrock Pampas Cat)" | sudo tee /etc/almalinux-release
sudo ./uninstall-cpanel.sh
# restore afterwards
sudo mv /etc/almalinux-release.bak /etc/almalinux-release 2>/dev/null
```

### 2. Pre-flight says "not running as root"

Use `sudo` or become root:

```bash
sudo -i
cd /root/cpanel-uninstaller
./uninstall-cpanel.sh
```

### 3. "Less than 1 GB free on /root"

Move the backup target or free space:

```bash
df -h /root
# EITHER
sudo ./uninstall-cpanel.sh --skip-backup
# OR (recommended)
# make room, e.g. clear /var/log/journal, old kernels, /tmp
sudo journalctl --vacuum-time=2d
sudo dnf autoremove -y
```

---

## During the run

### 4. Script aborts at phase 3 (stopping services)

Some cPanel services run under `tailwatchd` and may respawn. Run with
verbose mode to see which one:

```bash
sudo ./uninstall-cpanel.sh -v
```

If `tailwatchd` itself refuses to die:

```bash
sudo kill -9 $(pgrep -f tailwatchd)
sudo systemctl stop tailwatchd
sudo ./uninstall-cpanel.sh -v  # re-run
```

The script is idempotent, so re-running from scratch is safe.

### 5. `rpm -e` failures in phase 4

The script uses `rpm -e --nodeps --allmatches` to avoid cPanel's
notorious dependency knot. Individual failures are logged as warnings
and do not abort the run.

After the script finishes, check:

```bash
rpm -qa | grep -Ei '^(cpanel|ea-|alt-|MariaDB-)'
```

Anything left over can be removed with:

```bash
sudo rpm -qa | grep -Ei '^(cpanel|ea-|alt-)' | xargs -r sudo rpm -e --nodeps --allmatches
sudo rpm --rebuilddb
```

### 6. `firewall-cmd: not found`

`firewalld` may have been removed by cPanel's installer. Re-install:

```bash
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld
```

### 7. Script exits with "command not found" for bashisms

Ensure you're running under bash, not sh or dash:

```bash
sudo bash ./uninstall-cpanel.sh
```

### 8. SSH disconnects mid-run

Reconnect and re-run. The script is idempotent: completed phases simply
log "skip (not present)". Use tmux next time.

---

## After the run

### 9. Network is down after the script

Most common cause: NetworkManager was disabled.

```bash
sudo systemctl enable --now NetworkManager
sudo nmcli networking on
sudo nmcli con reload
sudo nmcli con up $(nmcli -t -f NAME con show | head -1)
```

If the interface is managed by `network.service` (legacy):

```bash
sudo systemctl enable --now network
```

### 10. DNS is broken (`getent hosts google.com` fails)

`/etc/resolv.conf` may be empty or malformed. Write a minimal one:

```bash
sudo tee /etc/resolv.conf >/dev/null <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
sudo chattr +i /etc/resolv.conf     # prevent NM from overwriting
```

Remove the immutable flag when NetworkManager is configured correctly:

```bash
sudo chattr -i /etc/resolv.conf
```

### 11. `dnf`/`yum` complains about missing repos

cPanel-specific repos are intentionally removed. If base repos are
missing too:

```bash
sudo dnf install -y \
    https://repo.almalinux.org/almalinux/almalinux-release-latest-9.noarch.rpm
sudo dnf clean all
sudo dnf makecache
```

### 12. `/home/<user>` directories orphaned

After the run, inspect:

```bash
ls /home
```

For directories that have no matching user in `/etc/passwd`, either:

- Re-create the user (if you want to keep data):
  ```bash
  sudo useradd -m -d /home/johndoe -u <old-uid> johndoe
  sudo chown -R johndoe:johndoe /home/johndoe
  ```
- Or archive them:
  ```bash
  sudo tar -C /home -czf /root/ex-cpanel-users.tar.gz <user>
  sudo rm -rf /home/<user>
  ```

### 13. Residual cron entries

```bash
sudo crontab -l
sudo grep -rE '(cpanel|cpbackup|exim)' /etc/cron.* /var/spool/cron/ 2>/dev/null
```

Delete anything referencing `/scripts/`, `cpbackup`, `eximstats`, etc.

### 14. `systemctl list-units --failed` shows stuff

```bash
sudo systemctl reset-failed
sudo systemctl list-units --failed
```

If the same unit keeps failing, it was likely a cPanel-installed
service file left behind. Find and remove:

```bash
find /etc/systemd/system /usr/lib/systemd/system -name '*cpanel*' -o -name 'ea-*' -o -name 'cpsrvd*'
sudo systemctl daemon-reload
```

### 15. SELinux denials

```bash
sudo ausearch -m avc -ts recent
```

If you see denials related to long-gone cPanel paths:

```bash
sudo restorecon -Rv /etc /var /home /usr
```

---

## Edge cases

### 16. CloudLinux instead of AlmaLinux

CloudLinux is a RHEL 9 derivative. This script does **not** officially
support it because CloudLinux has additional packages (`cagefs`, `lve`,
`lvemanager`, `alt-php`) that need separate handling. You'll need to run
CloudLinux's own uninstaller first:

```bash
sudo /usr/bin/cldeploy --to-centos
# reboot, then use this script
```

### 17. cPanel partition `/usr/local/cpanel` is on a separate disk

No special handling needed; `rm -rf --one-file-system` still works. The
device can be unmounted and reused:

```bash
umount /usr/local/cpanel
# remove corresponding /etc/fstab entry
```

### 18. Wanting to reverse the uninstall

This script does not support rollback. Reinstall cPanel fresh and restore
customer data from backup; see [REINSTALL.md](REINSTALL.md).

---

## Still stuck?

Open an issue at
<https://github.com/masharif46/cpanel-uninstaller/issues>
and include:

1. The full log file from `/var/log/cpanel-uninstaller/`.
2. Output of `cat /etc/almalinux-release && uname -a`.
3. Output of `rpm -qa | grep -Ei '^(cpanel|ea-)'` (if any).
4. What command you ran (flags included).
