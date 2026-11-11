#!/usr/bin/env bash
# Repository template generation + HTTP/HTTPS mirror selection

REPO_TEMPLATE="${TOOL_ROOT}/config/repos/sources.list.template"
DEBIAN_REPO_TEMPLATE="${TOOL_ROOT}/config/repos/debian.sources.list.template"
CODENAME_MAP="${TOOL_ROOT}/config/ubuntu-codenames.map"
IITD_MIRROR_SCHEME_FILE="${IITD_STATE_DIR:-/var/lib/iitd-tool/state}/mirror.scheme"
APT_REPO_DIRECT_FILE="/etc/apt/apt.conf.d/99iitd-repo-direct"

lookup_codename() {
    local version="$1"
    local map_file="${2:-${OS_CODENAME_MAP:-${CODENAME_MAP}}}"

    if [[ ! -f "${map_file}" ]]; then
        return 1
    fi

    local line codename
    while IFS='=' read -r line codename; do
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
        if [[ "${line}" == "${version}" ]]; then
            echo "${codename}"
            return 0
        fi
    done < "${map_file}"

    return 1
}

# http → classic ernet mirror; https → ac.in (cert SAN is *.iitd.ac.in)
iitd_mirror_base_for_scheme() {
    local scheme="${1:-http}"
    case "${scheme}" in
        https|HTTPS)
            printf '%s\n' "https://repo.iitd.ac.in"
            ;;
        *)
            printf '%s\n' "http://repo.iitd.ernet.in"
            ;;
    esac
}

iitd_mirror_scheme_normalize() {
    local scheme="${1:-http}"
    case "${scheme}" in
        https|HTTPS|2) printf '%s\n' "https" ;;
        *) printf '%s\n' "http" ;;
    esac
}

save_iitd_mirror_scheme() {
    local scheme
    scheme="$(iitd_mirror_scheme_normalize "${1:-http}")"
    mkdir -p "$(dirname "${IITD_MIRROR_SCHEME_FILE}")"
    printf '%s\n' "${scheme}" > "${IITD_MIRROR_SCHEME_FILE}"
    IITD_MIRROR_SCHEME="${scheme}"
    IITD_REPO_MIRROR_URL="$(iitd_mirror_base_for_scheme "${scheme}")/"
    export IITD_MIRROR_SCHEME IITD_REPO_MIRROR_URL
}

load_iitd_mirror_scheme() {
    local scheme="http"
    if [[ -f "${IITD_MIRROR_SCHEME_FILE}" ]]; then
        scheme="$(tr -d '[:space:]' < "${IITD_MIRROR_SCHEME_FILE}")"
    fi
    scheme="$(iitd_mirror_scheme_normalize "${scheme}")"
    IITD_MIRROR_SCHEME="${scheme}"
    IITD_REPO_MIRROR_URL="$(iitd_mirror_base_for_scheme "${scheme}")/"
    export IITD_MIRROR_SCHEME IITD_REPO_MIRROR_URL
}

prompt_iitd_mirror_scheme() {
    local choice scheme
    echo
    echo -e "${BOLD}IITD apt mirror protocol${NC}"
    echo "  1) HTTP  — http://repo.iitd.ernet.in  (classic)"
    echo "  2) HTTPS — https://repo.iitd.ac.in   (TLS; cert matches *.iitd.ac.in)"
    echo
    echo "Note: https://repo.iitd.ernet.in fails TLS name check (cert is only for *.iitd.ac.in)."
    echo
    read -r -p "Select mirror protocol [1=http, 2=https] (default 1): " choice
    case "${choice}" in
        2|https|HTTPS) scheme="https" ;;
        *) scheme="http" ;;
    esac
    save_iitd_mirror_scheme "${scheme}"
    log_info "Selected mirror: $(iitd_mirror_base_for_scheme "${scheme}")"
}

ensure_apt_repo_direct_bypass() {
    require_root
    cat > "${APT_REPO_DIRECT_FILE}" <<'EOF'
// Managed by iitd-tool / iitd-proxy. Internal IITD mirrors bypass campus proxy.
// Safe to keep after logout — Direct is a no-op when no proxy is set.
Acquire::http::Proxy::repo.iitd.ernet.in "DIRECT";
Acquire::https::Proxy::repo.iitd.ernet.in "DIRECT";
Acquire::http::Proxy::repo.iitd.ac.in "DIRECT";
Acquire::https::Proxy::repo.iitd.ac.in "DIRECT";
EOF
    chmod 644 "${APT_REPO_DIRECT_FILE}"
    log_success "APT internal-repo proxy bypass -> ${APT_REPO_DIRECT_FILE}"
}

generate_sources_list() {
    local os_version="$1"
    local os_codename="$2"
    local output_file="$3"
    local scheme="${4:-${IITD_MIRROR_SCHEME:-http}}"
    local template="${REPO_TEMPLATE}"
    local mirror_base

    scheme="$(iitd_mirror_scheme_normalize "${scheme}")"
    mirror_base="$(iitd_mirror_base_for_scheme "${scheme}")"

    if [[ "${OS_ID:-ubuntu}" == "debian" ]]; then
        template="${DEBIAN_REPO_TEMPLATE}"
    fi

    if [[ ! -f "${template}" ]]; then
        log_error "Repo template not found: ${template}"
        return 1
    fi

    if [[ -z "${os_codename}" ]]; then
        log_error "Release codename is required for repo setup"
        return 1
    fi

    sed \
        -e "s|<mirror_base>|${mirror_base}|g" \
        -e "s/<release>/${os_codename}/g" \
        -e "s/<version>/${os_version}/g" \
        "${template}" > "${output_file}"

    log_success "Generated sources.list for ${os_version} (${os_codename}) via ${mirror_base}"
}
