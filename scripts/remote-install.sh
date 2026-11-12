#!/usr/bin/env bash
# Bootstrap: download IITD Lab Setup Tool from hobbit2 and install system-wide.
#
# One-liner:
#   curl -fsSL http://hobbit2.cse.iitd.ac.in:8080/iitd-tools/install.sh | bash
#
# Safer (same result):
#   curl -fsSL http://hobbit2.cse.iitd.ac.in:8080/iitd-tools/install.sh -o /tmp/iitd-install.sh && bash /tmp/iitd-install.sh

set -euo pipefail

BASE_URL="${IITD_TOOLS_URL:-http://hobbit2.cse.iitd.ac.in:8080/iitd-tools}"
TARBALL_URL="${BASE_URL%/}/iitd_tools.tar.gz"
WORKDIR="${IITD_TOOLS_WORKDIR:-/tmp/iitd-tools-install}"

# curl|bash feeds the script on stdin — reattach a real terminal for sudo / prompts.
if [[ ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
        exec </dev/tty
    else
        echo "[ERROR] No interactive terminal for sudo/password prompts." >&2
        echo "        Run:" >&2
        echo "          curl -fsSL ${BASE_URL%/}/install.sh -o /tmp/iitd-install.sh && bash /tmp/iitd-install.sh" >&2
        exit 1
    fi
fi

echo "IITD Lab Setup Tool — remote install"
echo "  Source: ${TARBALL_URL}"
echo

rm -rf "${WORKDIR}"
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

if [[ ! -s iitd_tools.tar.gz ]]; then
    echo "[ERROR] Download failed or empty archive: ${TARBALL_URL}" >&2
    exit 1
fi

tar xzf iitd_tools.tar.gz
if [[ ! -f iitd_tools/install-iitd-tool.sh || ! -f iitd_tools/iitd-config ]]; then
    echo "[ERROR] Archive is incomplete (missing install-iitd-tool.sh / iitd-config)." >&2
    exit 1
fi

cd iitd_tools
chmod +x install-iitd-tool.sh iitd-tool iitd-config scripts/iitd-proxy 2>/dev/null || true

# Install only — staff-proxy menu used to make a cancelled login look like install failure.
export IITD_INSTALL_ONLY=1
bash ./install-iitd-tool.sh "$@"
rc=$?

if [[ "${rc}" -ne 0 ]]; then
    echo "[ERROR] Install failed (exit ${rc})." >&2
    exit "${rc}"
fi

echo
echo "=============================================="
echo " Install complete."
echo "=============================================="
echo
echo "Start the tool anytime with:"
echo "  sudo iitd-tool"
echo
read -r -p "Start iitd-tool now (staff proxy login + menu)? [y/N]: " reply || true
if [[ "${reply}" =~ ^[Yy]$ ]]; then
    if [[ -x /usr/local/bin/iitd-tool ]]; then
        exec /usr/local/bin/iitd-tool
    fi
    exec bash ./iitd-tool
fi

echo "Done."
exit 0
