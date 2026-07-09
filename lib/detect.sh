#!/usr/bin/env bash
# Ubuntu version detection

UBUNTU_MIN_VERSION="16.04"
UBUNTU_MAX_VERSION="26.04"

version_in_range() {
    local version="$1"
    local min="$2"
    local max="$3"

    [[ "$(printf '%s\n' "${min}" "${version}" | sort -V | head -1)" == "${min}" ]] &&
        [[ "$(printf '%s\n' "${version}" "${max}" | sort -V | head -1)" == "${version}" ]]
}

resolve_ubuntu_codename() {
    local version="$1"
    local codename="${2:-}"

    if [[ -n "${codename}" ]]; then
        echo "${codename}"
        return 0
    fi

    lookup_codename "${version}"
}

detect_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_error "This tool supports Ubuntu only. Detected: ${ID:-unknown}"
        exit 1
    fi

    UBUNTU_VERSION="${VERSION_ID}"
    UBUNTU_CODENAME="${VERSION_CODENAME:-}"
    UBUNTU_PRETTY="${PRETTY_NAME}"

    if ! version_in_range "${UBUNTU_VERSION}" "${UBUNTU_MIN_VERSION}" "${UBUNTU_MAX_VERSION}"; then
        log_error "Unsupported Ubuntu version: ${UBUNTU_VERSION}"
        log_error "Supported range: ${UBUNTU_MIN_VERSION} to ${UBUNTU_MAX_VERSION}"
        exit 1
    fi

    UBUNTU_CODENAME="$(resolve_ubuntu_codename "${UBUNTU_VERSION}" "${UBUNTU_CODENAME}")" || {
        log_error "Cannot determine release codename for Ubuntu ${UBUNTU_VERSION}"
        log_error "Add an entry to ${TOOL_ROOT}/config/ubuntu-codenames.map"
        exit 1
    }

    export UBUNTU_VERSION UBUNTU_CODENAME UBUNTU_PRETTY
}

print_system_info() {
    echo -e "${BOLD}System:${NC} ${UBUNTU_PRETTY}"
    echo -e "${BOLD}Version:${NC} ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"
    echo
}
