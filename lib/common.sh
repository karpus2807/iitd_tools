#!/usr/bin/env bash
# Shared utilities for IITD Lab Setup Tool

set -euo pipefail

# Colors (disabled when not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Root privileges required. Run: sudo $0"
        exit 1
    fi
}

confirm() {
    local prompt="${1:-Continue?}"
    local reply
    read -r -p "${prompt} [y/N]: " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

backup_file() {
    local file="$1"
    local backup_dir="${2:-/etc/apt/iitd-tool-backup}"

    if [[ ! -f "${file}" ]]; then
        return 0
    fi

    mkdir -p "${backup_dir}"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local basename
    basename="$(basename "${file}")"
    cp -a "${file}" "${backup_dir}/${basename}.${timestamp}.bak"
    log_info "Backed up ${file} -> ${backup_dir}/${basename}.${timestamp}.bak"
}

pause() {
    read -r -p "Press Enter to continue..."
}
