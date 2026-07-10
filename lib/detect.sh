#!/usr/bin/env bash
# Ubuntu / Debian version detection

UBUNTU_MIN_VERSION="16.04"
UBUNTU_MAX_VERSION="26.04"
DEBIAN_MIN_VERSION="10"
DEBIAN_MAX_VERSION="13"

version_in_range() {
    local version="$1"
    local min="$2"
    local max="$3"

    [[ "$(printf '%s\n' "${min}" "${version}" | sort -V | head -1)" == "${min}" ]] &&
        [[ "$(printf '%s\n' "${version}" "${max}" | sort -V | head -1)" == "${version}" ]]
}

resolve_os_codename() {
    local version="$1"
    local codename="${2:-}"
    local map_file="$3"

    if [[ -n "${codename}" ]]; then
        echo "${codename}"
        return 0
    fi

    lookup_codename "${version}" "${map_file}"
}

_detect_supported_os() {
    case "${ID:-}" in
        ubuntu|debian)
            return 0
            ;;
        *)
            if [[ "${ID_LIKE:-}" == *"debian"* || "${ID_LIKE:-}" == *"ubuntu"* ]]; then
                return 0
            fi
            return 1
            ;;
    esac
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if ! _detect_supported_os; then
        log_error "This tool supports Ubuntu and Debian only. Detected: ${ID:-unknown}"
        exit 1
    fi

    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    OS_PRETTY="${PRETTY_NAME}"

    case "${OS_ID}" in
        debian)
            OS_CODENAME_MAP="${TOOL_ROOT}/config/debian-codenames.map"
            IITD_REPO_MIRROR_URL="http://repo.iitd.ernet.in/debian/"
            if ! version_in_range "${OS_VERSION}" "${DEBIAN_MIN_VERSION}" "${DEBIAN_MAX_VERSION}"; then
                log_error "Unsupported Debian version: ${OS_VERSION}"
                log_error "Supported range: ${DEBIAN_MIN_VERSION} to ${DEBIAN_MAX_VERSION}"
                exit 1
            fi
            ;;
        ubuntu|*)
            OS_ID="ubuntu"
            OS_CODENAME_MAP="${TOOL_ROOT}/config/ubuntu-codenames.map"
            IITD_REPO_MIRROR_URL="http://repo.iitd.ernet.in/ubuntu/"
            if ! version_in_range "${OS_VERSION}" "${UBUNTU_MIN_VERSION}" "${UBUNTU_MAX_VERSION}"; then
                log_error "Unsupported Ubuntu version: ${OS_VERSION}"
                log_error "Supported range: ${UBUNTU_MIN_VERSION} to ${UBUNTU_MAX_VERSION}"
                exit 1
            fi
            ;;
    esac

    OS_CODENAME="$(resolve_os_codename "${OS_VERSION}" "${OS_CODENAME}" "${OS_CODENAME_MAP}")" || {
        log_error "Cannot determine release codename for ${OS_ID} ${OS_VERSION}"
        log_error "Add an entry to ${OS_CODENAME_MAP}"
        exit 1
    }

    # Backward-compatible names used across modules
    UBUNTU_VERSION="${OS_VERSION}"
    UBUNTU_CODENAME="${OS_CODENAME}"
    UBUNTU_PRETTY="${OS_PRETTY}"

    export OS_ID OS_VERSION OS_CODENAME OS_PRETTY OS_CODENAME_MAP IITD_REPO_MIRROR_URL
    export UBUNTU_VERSION UBUNTU_CODENAME UBUNTU_PRETTY
}

detect_ubuntu() {
    detect_os
}

print_system_info() {
    echo -e "${BOLD}System:${NC} ${OS_PRETTY:-${UBUNTU_PRETTY}}"
    echo -e "${BOLD}OS:${NC} ${OS_ID:-ubuntu} ${OS_VERSION:-${UBUNTU_VERSION}} (${OS_CODENAME:-${UBUNTU_CODENAME}})"
    echo
}

official_sources_filename() {
    if [[ "${OS_ID:-ubuntu}" == "debian" ]]; then
        echo "debian.sources"
    else
        echo "ubuntu.sources"
    fi
}
