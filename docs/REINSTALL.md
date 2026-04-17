# Reinstalling cPanel / WHM After Uninstall

This guide covers a clean cPanel reinstall on the same AlmaLinux 9 server
after you have run `uninstall-cpanel.sh`.

The official cPanel installer insists on a "fresh" OS. Our uninstaller
leaves the system in a state that *passes* cPanel's pre-install checks,
but there are still a few steps to do.

---

## 1. Reboot first

```bash
sudo systemctl reboot
```

This clears any kernel modules, tmpfiles, or supervisor processes left
over from cPanel. Do not skip this step.

## 2. Verify the system is ready

```bash
sudo ./scripts/post-verify.sh
```

Fix any `[FAIL]` items before proceeding. Warnings can usually be
ignored for a reinstall.

## 3. Confirm pre-install prerequisites

cPanel's own [prerequisites](https://docs.cpanel.net/installation-guide/system-requirements-for-cpanel-whm/):

- Fresh OS (AlmaLinux 9.x) – ✅ after uninstall + reboot.
- No Apache, PHP, MySQL, Dovecot, Exim, Pure-FTPd, NetworkManager
  conflicts – ✅ we removed those.
- At least **1 GB RAM** (2 GB recommended; 4 GB+ for production).
- At least **20 GB disk**.
- Static IP address / valid FQDN hostname.
- SELinux can be enforcing, but `permissive` is less error-prone:

  ```bash
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
  ```

- Hostname must resolve:

  ```bash
  sudo hostnamectl set-hostname server.example.com
  echo "1.2.3.4 server.example.com server" | sudo tee -a /etc/hosts
  ```

- Ensure basic tools:

  ```bash
  sudo dnf install -y perl curl wget tar bzip2 gcc make
  ```

## 4. Run the cPanel installer

```bash
cd /home
sudo curl -o latest -L https://securedownloads.cpanel.net/latest
sudo sh latest
```

The installer will take 30–60 minutes, depending on hardware and network.

Progress is written to `/var/log/cpanel-install.log`. You can tail it:

```bash
tail -f /var/log/cpanel-install.log
```

## 5. After installation

1. **Activate your license.** A trial license auto-activates for the
   server IP. For a paid license, run:

   ```bash
   sudo /usr/local/cpanel/cpkeyclt
   ```

2. **Login to WHM:**

   ```
   https://<server-ip>:2087
   ```

3. **Run the Initial Setup Wizard.** Skip any step you plan to configure
   manually.

4. **EasyApache 4 / PHP**

   ```bash
   sudo /scripts/easyapache4
   ```

   Choose the profile that best matches your site (WP, LAMP stock, etc.).

5. **Firewall.** Re-enable CSF or configure `firewalld` rules for your
   needs.

6. **Migrate customer data.** If you ran the uninstall with
   `--keep-home --keep-mysql` and kept your `/var/cpanel/users` backups,
   you can import accounts:

   ```bash
   for u in /root/cpanel-uninstall-backup-*/var/cpanel/users/*; do
       sudo /scripts/restorepkg "${u##*/}"
   done
   ```

   For full migration, use WHM → *Transfer Tool* or:

   ```bash
   sudo /scripts/restorepkg --from=/path/to/backup.tar.gz account-name
   ```

## 6. Verify

- WHM → *Server Status* → all services green.
- `sudo /scripts/upcp --force` (force update to pick up latest version).
- `sudo /usr/local/cpanel/scripts/check_cpanel_rpms --fix` (fix any RPM
  issues).
- `systemctl list-units --failed` should be empty.

## 7. Tuning recommendations

Only relevant to a new installation; skip if you're restoring a prod box.

```bash
# cPanel configuration tweaks
sudo /scripts/update_local_rpm_versions --edit target_settings.MySQL 8.0
sudo /scripts/cpanel_initial_install --force
```

Tweak `/etc/my.cnf`, `/var/cpanel/cpanel.config`, and
`/usr/local/apache/conf/httpd.conf` (via WHM → *Global Configuration*)
rather than editing them by hand.

---

## Troubleshooting a reinstall failure

| Symptom                                      | Fix                                                          |
|----------------------------------------------|--------------------------------------------------------------|
| "This server is not a fresh install"         | Double-check `/usr/local/cpanel` and `/var/cpanel` are gone. |
| `yum/dnf` complains about MariaDB            | Remove the old repo: `rm /etc/yum.repos.d/MariaDB*`          |
| Hostname not resolvable                      | Set with `hostnamectl` and add to `/etc/hosts`.              |
| Port 2087 blocked                            | `firewall-cmd --add-port=2087/tcp --permanent && firewall-cmd --reload` |
| `cpanel-dovecot-solr` fails to start         | Ensure `/var/cpanel-dovecot-solr` does not exist before install. |
| `yum` no repos after uninstall               | `dnf install -y epel-release` if needed, then re-run installer. |

See also [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for general issues.
