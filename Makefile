# Convenience Makefile for the cpanel-uninstaller project
# Not required for end users — developers only.

SHELL := /bin/bash
SCRIPTS := uninstall-cpanel.sh $(wildcard lib/*.sh) $(wildcard scripts/*.sh)

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: lint
lint: ## Run ShellCheck on all scripts
	@shellcheck -e SC1091 -e SC2034 -e SC2086 -x $(SCRIPTS)
	@echo "ShellCheck passed."

.PHONY: format
format: ## Normalize line endings to LF
	@find . -type f \( -name '*.sh' -o -name '*.md' \) -print0 | \
		xargs -0 dos2unix -q 2>/dev/null || true
	@echo "Line endings normalised."

.PHONY: chmod
chmod: ## Set executable bits
	@chmod +x uninstall-cpanel.sh
	@chmod +x lib/*.sh scripts/*.sh
	@echo "Executable bits set."

.PHONY: dryrun
dryrun: chmod ## Run --dry-run locally (root required)
	@sudo ./uninstall-cpanel.sh --dry-run --verbose

.PHONY: tarball
tarball: ## Create a release tarball
	@NAME=cpanel-uninstaller-$$(git describe --tags --always 2>/dev/null || date +%Y%m%d); \
	tar --exclude='.git' --exclude='*.log' --exclude='cpanel-uninstall-backup-*' \
		-czf ../$$NAME.tar.gz -C .. $$(basename $$PWD); \
	echo "Tarball: ../$$NAME.tar.gz"

.PHONY: clean
clean: ## Remove local logs & backups
	@rm -rf logs/ *.log cpanel-uninstall-backup-* *.tar.gz
	@echo "Cleaned."
