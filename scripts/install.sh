#!/usr/bin/env bash
# scripts/install.sh
# One-liner installer: downloads the latest release tarball from GitHub,
# extracts it to /opt, and prints next-step instructions.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/masharif46/cpanel-uninstaller/main/scripts/install.sh | sudo bash
#

set -Eeuo pipefail

REPO="${REPO:-masharif46/cpanel-uninstaller}"
BRANCH="${BRANCH:-main}"
DEST="${DEST:-/opt/cpanel-uninstaller}"

echo "[installer] downloading ${REPO}@${BRANCH} to ${DEST}..."

if [[ ${EUID} -ne 0 ]]; then
    echo "This installer must run as root." >&2
    exit 2
fi

if [[ -d "${DEST}" ]]; then
    echo "[installer] ${DEST} already exists — updating..."
    rm -rf "${DEST}"
fi

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" \
    | tar -xz -C "${tmp}"

mv "${tmp}"/*-"${BRANCH}" "${DEST}"

chmod +x "${DEST}/uninstall-cpanel.sh" \
         "${DEST}"/lib/*.sh \
         "${DEST}"/scripts/*.sh

echo
echo "[installer] installed to ${DEST}"
echo
echo "Next steps:"
echo "  cd ${DEST}"
echo "  sudo ./scripts/pre-check.sh"
echo "  sudo ./uninstall-cpanel.sh --dry-run      # preview"
echo "  sudo ./uninstall-cpanel.sh                # real run"
echo
