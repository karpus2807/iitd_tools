#!/usr/bin/env bash
# IITD Lab Setup Tool — portable pendrive launcher
#
# Copy the whole iitd_tool folder to a USB drive, then on any Ubuntu system:
#   bash install-iitd-tool.sh
#
# Asks for sudo once, installs the tool system-wide, then opens the main menu.

set -euo pipefail

_script="$(readlink -f "${BASH_SOURCE[0]}")"
TOOL_DIR="$(cd "$(dirname "${_script}")" && pwd)"

if [[ ! -f "${TOOL_DIR}/iitd-config" ]]; then
    echo "[ERROR] iitd-config not found next to this script." >&2
    echo "        Run this from the iitd_tool folder on the pendrive." >&2
    exit 1
fi

# Ask sudo password once and re-run as root with the same tool directory.
if [[ "${EUID}" -ne 0 ]]; then
    echo "IITD Lab Setup Tool — portable install"
    echo
    echo "  Source: ${TOOL_DIR}"
    echo
    echo "Administrator (sudo) access is required to install and run this tool."
    exec sudo -E bash "${_script}" "$@"
fi

chmod +x "${TOOL_DIR}/iitd-config" "${TOOL_DIR}/iitd-tool" 2>/dev/null || true
chmod +x "${TOOL_DIR}/scripts/iitd-proxy" 2>/dev/null || true

echo
echo "Installing / updating IITD tool on this system..."
echo

export TOOL_ROOT="${TOOL_DIR}"
"${TOOL_DIR}/iitd-tool" install --yes

echo
echo "Starting IITD Lab Setup Tool..."
echo

if [[ -x /usr/local/bin/iitd-tool ]]; then
    exec /usr/local/bin/iitd-tool
fi

exec "${TOOL_DIR}/iitd-tool"
