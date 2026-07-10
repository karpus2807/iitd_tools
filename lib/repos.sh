#!/usr/bin/env bash
# Repository template generation

REPO_TEMPLATE="${TOOL_ROOT}/config/repos/sources.list.template"
DEBIAN_REPO_TEMPLATE="${TOOL_ROOT}/config/repos/debian.sources.list.template"
CODENAME_MAP="${TOOL_ROOT}/config/ubuntu-codenames.map"

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

generate_sources_list() {
    local os_version="$1"
    local os_codename="$2"
    local output_file="$3"
    local template="${REPO_TEMPLATE}"

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
        -e "s/<release>/${os_codename}/g" \
        -e "s/<version>/${os_version}/g" \
        "${template}" > "${output_file}"

    log_success "Generated sources.list for ${os_version} (${os_codename})"
}
