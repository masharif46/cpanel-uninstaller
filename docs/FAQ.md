# Frequently Asked Questions

## General

### Is this supported by cPanel?

No. cPanel's only officially supported uninstall procedure is to
reinstall the operating system. This project is a community effort that
deliberately removes cPanel's footprint while preserving the base OS.
Use at your own risk.

### Will I lose my customer data?

By default:

- `/home/<real-user>` contents are **preserved** (only cPanel-system
  homes like `/home/virtfs`, `/home/cpeasyapache`, `/home/cpanel*` are
  removed).
- MySQL databases (`/var/lib/mysql`) are **removed** unless you pass
  `--keep-mysql`.
- Mail spools under `/var/spool/mail` and virtual mail under
  `/home/<user>/mail` are preserved as part of `/home`.

Always take an off-host backup before running this script.

### Can I migrate accounts after uninstall?

Yes, if you pass `--keep-home --keep-mysql`. The cPanel account files
under `/var/cpanel/users` are backed up to
`/root/cpanel-uninstall-backup-<ts>/`, and you can import them on a
freshly installed cPanel via `/scripts/restorepkg`. See
[REINSTALL.md §5](REINSTALL.md).

---

## Compatibility

### Does it work on RHEL 9 or Rocky Linux 9?

Technically it should — they use the same package set and same systemd
/ cPanel integration. But the script is only **tested on AlmaLinux 9**
and intentionally refuses to run on other distributions.

See [TROUBLESHOOTING §1](TROUBLESHOOTING.md#1-this-script-only-supports-almalinux-9)
for a workaround if you want to try.

### What about AlmaLinux 8?

Not supported. cPanel 110+ on AlmaLinux 9 uses systemd unit paths,
`dnf`, and PHP/Perl locations different from AlmaLinux 8. If you need
AlmaLinux 8 support, open an issue.

### What about CloudLinux?

Not supported out of the box — CloudLinux adds `cagefs`, `lve`, `alt-php`
stacks that need their own uninstall sequence. Convert back to AlmaLinux
first (`/usr/bin/cldeploy --to-centos`), then run this script.

---

## Safety

### Will `ssh` still work after uninstall?

Yes. The uninstaller explicitly re-enables `sshd` in phase 8 and
post-verifies that it is listening on port 22 before printing the
"safe to reboot" message.

That said, **always run the script inside tmux or screen** in case your
connection drops mid-run.

### Will my IP address / network config change?

No. The script does not touch `/etc/sysconfig/network-scripts/`,
NetworkManager connections, or routing tables. It only rewrites
`/etc/hosts` with a minimal entry for `localhost` and your hostname.

### Is `/etc/hosts` always rewritten?

Yes. cPanel often adds custom entries to `/etc/hosts`. The script makes
a timestamped backup (`/etc/hosts.bak.cpanel-uninstall`) and replaces
the file with a minimal, correct one. Edit it afterwards if you had
custom entries.

### Is SELinux disabled?

No. The script does not modify SELinux state. Your current enforcing/
permissive/disabled setting is untouched.

### Could the script brick my server?

In theory any script that runs `rm -rf` as root can break things.
Safeguards:

- `set -Eeuo pipefail` + `ERR` trap
- `--one-file-system` on every `rm`
- Explicit path whitelist (no wildcards like `/usr/*`)
- Double confirmation (`REMOVE CPANEL` + `yes`)
- Dry-run mode
- Pre and post checks

That said, **always keep an off-host backup** and rescue-boot access.

---

## Operation

### How long does it take?

On a 4-core, 8 GB RAM VPS with 50 GB cPanel data: ~5-10 minutes. The
backup phase is usually the slowest.

### Can I run it on a live server with customers?

Technically yes, but:

- Customers will lose service the moment services are stopped (phase 3).
- Websites, email, FTP, and databases all go offline.
- Plan a maintenance window and notify customers.

### Can it run unattended (e.g. in a cloud-init)?

Yes — pass `-f --skip-backup` (or `-f` with a `--backup-dir` if you
want to keep it):

```bash
sudo ./uninstall-cpanel.sh -f -k
```

### Is there a rollback?

No automatic rollback. The safety backup under
`/root/cpanel-uninstall-backup-<ts>/` is for reference and partial manual
recovery only. Rollback means: reinstall cPanel fresh, then restore
customer data from your own backup.

---

## Reinstallation

### Can I reinstall cPanel immediately?

Yes — see [REINSTALL.md](REINSTALL.md). Best practice:

1. Reboot.
2. Run `scripts/post-verify.sh` to confirm health.
3. Run the cPanel installer:

   ```bash
   cd /home
   curl -o latest -L https://securedownloads.cpanel.net/latest
   sh latest
   ```

### Will my cPanel license still work?

Yes — IP-based licenses auto-activate once cPanel is installed again.
If you own a transferable license, you may need to release it from the
Manage2 dashboard first.

### Does the uninstaller delete my cPanel license?

No. Licenses live on cPanel, L.L.C.'s servers, not on your box. The
only local license artifact (`/etc/wwwacct.conf` and the license file)
is removed, but this has no effect on the upstream license.

---

## Extending the script

### I want to skip one phase

Each phase is its own function in `uninstall-cpanel.sh`. Comment out
the `phase_*` call in `main()` you want to skip:

```bash
# phase_firewall_cleanup      # uncomment to skip
```

### I want to add a phase

1. Add a function `phase_mything()` in the main script.
2. Create `lib/mything.sh` with the actual commands.
3. `source` it alongside the other libs (top of main script already
   loops over `common services packages users cleanup firewall` — add
   `mything`).
4. Call `phase_mything()` from `main()`.

### How do I test without breaking the server?

Use `--dry-run`:

```bash
sudo ./uninstall-cpanel.sh --dry-run --verbose | less
```

Every destructive command is prefixed with `[DRY-RUN]` and not
executed.

---

## Project

### License?

MIT — see [LICENSE](../LICENSE).

### Can I fork and modify?

Yes — please do. Attribution appreciated but not required. PRs welcome.

### How do I report a bug?

Open an issue and include the full log from
`/var/log/cpanel-uninstaller/uninstall-<ts>.log`.
