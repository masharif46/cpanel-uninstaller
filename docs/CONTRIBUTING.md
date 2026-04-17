# Contributing

Thanks for taking the time to contribute!

## Development workflow

1. Fork & clone the repo.
2. Create a topic branch: `git checkout -b fix/<short-name>`
3. Make changes.
4. Run **ShellCheck** on every file you touched:

   ```bash
   shellcheck uninstall-cpanel.sh lib/*.sh scripts/*.sh
   ```

5. Test with `--dry-run` on an AlmaLinux 9 VM:

   ```bash
   sudo ./uninstall-cpanel.sh --dry-run --verbose
   ```

6. If you can, test a real uninstall on a throw-away VM. VirtualBox,
   libvirt, or a 1 USD/month VPS is plenty.
7. Commit with a descriptive message (`fix:`, `feat:`, `docs:`, `ci:`).
8. Push and open a PR.

## Coding style

- Bash 4+ features are OK.
- Prefer **named helper functions** over inline complexity.
- All destructive commands go through `run_cmd` / `safe_cmd` /
  `remove_path` so `--dry-run` works.
- Keep line length ≤ 100 chars.
- Two-space indent.
- No `curl | bash`; everything must be offline-safe.

## Pull request checklist

- [ ] Code passes `shellcheck`.
- [ ] `--dry-run` produces no errors on a test VM.
- [ ] Added/updated `docs/*.md` where appropriate.
- [ ] CHANGELOG entry (if present).
- [ ] License: by contributing you agree your work is released under
      the MIT License of this repo.

## Reporting a security issue

Please **do not** open a public GitHub issue for security-sensitive
reports. Open a private [security advisory](https://github.com/masharif46/cpanel-uninstaller/security/advisories/new)
instead.
