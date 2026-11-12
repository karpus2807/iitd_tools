#!/usr/bin/env bash
# Bootstrap: download IITD Lab Setup Tool from hobbit2 and install system-wide.
#
# One-liner (any Ubuntu/Debian lab PC that can reach hobbit2):
#   curl -fsSL http://hobbit2.cse.iitd.ac.in:8080/iitd-tools/install.sh | bash
#
# Or:
#   wget -qO- http://hobbit2.cse.iitd.ac.in:8080/iitd-tools/install.sh | bash

set -euo pipefail

BASE_URL="${IITD_TOOLS_URL:-http://hobbit2.cse.iitd.ac.in:8080/iitd-tools}"
TARBALL_URL="${BASE_URL%/}/iitd_tools.tar.gz"
WORKDIR="${TMPDIR:-/tmp}/iitd-tools-install.$$"

cleanup() {
    rm -rf "${WORKDIR}" 2>/dev/null || true
}
trap cleanup EXIT

echo "IITD Lab Setup Tool — remote install"
echo "  Source: ${TARBALL_URL}"
echo

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 600 "${TARBALL_URL}" -o iitd_tools.tar.gz
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=600 -O iitd_tools.tar.gz "${TARBALL_URL}"
else
    echo "[ERROR] Need curl or wget to download the tool." >&2
    exit 1
fi

tar xzf iitd_tools.tar.gz
if [[ ! -d iitd_tools ]]; then
    echo "[ERROR] Archive missing iitd_tools/ directory." >&2
    exit 1
fi

cd iitd_tools
chmod +x install-iitd-tool.sh iitd-tool iitd-config 2>/dev/null || true
exec bash ./install-iitd-tool.sh "$@"
