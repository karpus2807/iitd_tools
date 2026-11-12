#!/usr/bin/env bash
# IITD Lab Setup Tool — portable / remote installer
#
# Pendrive:
#   bash install-iitd-tool.sh
#
# Remote (hobbit2):
#   curl -fsSL http://hobbit2.cse.iitd.ac.in:8080/iitd-tools/install.sh | bash
#
# Asks for sudo once and installs the tool system-wide.
# Set IITD_INSTALL_ONLY=1 to skip auto-starting the interactive menu.

set -euo pipefail

_script="$(readlink -f "${BASH_SOURCE[0]}")"
TOOL_DIR="$(cd "$(dirname "${_script}")" && pwd)"

if [[ ! -f "${TOOL_DIR}/iitd-config" ]]; then
    echo "[ERROR] iitd-config not found next to this script." >&2
    echo "        Run this from the iitd_tool folder (or use the hobbit2 install.sh)." >&2
    exit 1
fi

# curl|bash / missing TTY: reattach console so sudo can ask for a password.
if [[ "${EUID}" -ne 0 ]] && [[ ! -t 0 ]] && [[ -r /dev/tty ]]; then
    exec bash "${_script}" "$@" </dev/tty
fi

# Ask sudo password once and re-run as root with the same tool directory.
if [[ "${EUID}" -ne 0 ]]; then
    echo "IITD Lab Setup Tool — portable install"
    echo
    echo "  Source: ${TOOL_DIR}"
    echo
    echo "Administrator (sudo) access is required to install this tool."
    if [[ -r /dev/tty ]]; then
        exec sudo -E bash "${_script}" "$@" </dev/tty
    fi
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
echo "[OK] System install finished."
echo "  Command: sudo iitd-tool"
echo

# Remote hobbit bootstrap sets this so a cancelled staff-proxy prompt
# is not mistaken for an install failure.
if [[ "${IITD_INSTALL_ONLY:-0}" == "1" ]]; then
    exit 0
fi

echo "Starting IITD Lab Setup Tool..."
echo

if [[ -x /usr/local/bin/iitd-tool ]]; then
    exec /usr/local/bin/iitd-tool
fi

exec "${TOOL_DIR}/iitd-tool"
