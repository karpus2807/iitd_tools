#!/usr/bin/env bash
# Repository template generation

REPO_TEMPLATE="${TOOL_ROOT}/config/repos/sources.list.template"
CODENAME_MAP="${TOOL_ROOT}/config/ubuntu-codenames.map"

lookup_codename() {
    local version="$1"

    if [[ ! -f "${CODENAME_MAP}" ]]; then
        return 1
    fi

    local line codename
    while IFS='=' read -r line codename; do
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
        if [[ "${line}" == "${version}" ]]; then
            echo "${codename}"
            return 0
        fi
    done < "${CODENAME_MAP}"

    return 1
}

generate_sources_list() {
    local ubuntu_version="$1"
    local ubuntu_codename="$2"
    local output_file="$3"

    if [[ ! -f "${REPO_TEMPLATE}" ]]; then
        log_error "Repo template not found: ${REPO_TEMPLATE}"
        return 1
    fi

    if [[ -z "${ubuntu_codename}" ]]; then
        log_error "Ubuntu codename (release) is required for repo setup"
        return 1
    fi

    sed \
        -e "s/<release>/${ubuntu_codename}/g" \
        -e "s/<version>/${ubuntu_version}/g" \
        "${REPO_TEMPLATE}" > "${output_file}"

    log_success "Generated sources.list for ${ubuntu_version} (${ubuntu_codename})"
}
