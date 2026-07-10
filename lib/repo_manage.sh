#!/usr/bin/env bash
# APT repository management (submenu actions)

SOURCES_LIST="/etc/apt/sources.list"
SOURCES_LIST_D="/etc/apt/sources.list.d"
UBUNTU_SOURCES="${SOURCES_LIST_D}/ubuntu.sources"
DEBIAN_SOURCES="${SOURCES_LIST_D}/debian.sources"

_manifest_add() {
    local key="$1"
    local value="$2"
    init_iitd_data_dirs
    echo "${key}=${value}" >> "${IITD_REPO_MANIFEST}"
}

_manifest_has_key() {
    local key="$1"
    [[ -f "${IITD_REPO_MANIFEST}" ]] && grep -q "^${key}=" "${IITD_REPO_MANIFEST}" 2>/dev/null
}

_save_original_once() {
    local file="$1"
    local label="$2"
    local original="${IITD_BACKUP_DIR}/${label}.original"

    init_iitd_data_dirs
    if [[ -f "${file}" && ! -f "${original}" ]]; then
        cp -a "${file}" "${original}"
        log_info "Original snapshot saved: ${original}"
    fi
}

_backup_timestamped() {
    local file="$1"
    local label="$2"
    local dest

    init_iitd_data_dirs
    dest="${IITD_BACKUP_DIR}/${label}.$(date +%Y%m%d_%H%M%S).bak"
    cp -a "${file}" "${dest}"
    log_success "Backup: ${dest}"
    echo "${dest}"
}

repo_action_backup_sources() {
    require_root
    init_iitd_data_dirs

    if [[ ! -f "${SOURCES_LIST}" ]]; then
        log_warn "sources.list not found: ${SOURCES_LIST}"
        return 1
    fi

    _save_original_once "${SOURCES_LIST}" "sources.list"
    _backup_timestamped "${SOURCES_LIST}" "sources.list" >/dev/null
    _manifest_add "sources_list" "modified"
    log_success "sources.list backed up to ${IITD_BACKUP_DIR}"
}

repo_action_apply_iitd_mirror() {
    local ubuntu_version="$1"
    local ubuntu_codename="$2"
    local temp_sources

    require_root
    init_iitd_data_dirs

    if [[ -f "${SOURCES_LIST}" ]]; then
        _save_original_once "${SOURCES_LIST}" "sources.list"
    fi

    temp_sources="$(mktemp)"
    if ! generate_sources_list "${ubuntu_version}" "${ubuntu_codename}" "${temp_sources}"; then
        rm -f "${temp_sources}"
        return 1
    fi

    cp "${temp_sources}" "${SOURCES_LIST}"
    rm -f "${temp_sources}"
    chmod 644 "${SOURCES_LIST}"
    _manifest_add "sources_list" "iitd"
    log_success "IITD mirror applied -> ${SOURCES_LIST}"
}

repo_action_disable_ubuntu_sources() {
    require_root
    init_iitd_data_dirs

    local official_name official_path
    official_name="$(official_sources_filename)"
    official_path="${SOURCES_LIST_D}/${official_name}"

    if [[ ! -f "${official_path}" ]]; then
        log_info "${official_name} not found (may already be disabled)"
        return 0
    fi

    _save_original_once "${official_path}" "${official_name}"
    _backup_timestamped "${official_path}" "${official_name}" >/dev/null
    mv "${official_path}" "${official_path}.disabled"
    _manifest_add "official_sources" "disabled"
    _manifest_add "official_sources_name" "${official_name}"
    log_success "Disabled: ${official_path} -> ${official_path}.disabled"
}

repo_action_disable_third_party() {
    require_root
    init_iitd_data_dirs

    local f base disabled=0

    shopt -s nullglob
    for f in "${SOURCES_LIST_D}"/*; do
        [[ -f "${f}" ]] || continue
        base="$(basename "${f}")"

        [[ "${base}" == *.disabled ]] && continue
        [[ "${base}" == "ubuntu.sources" ]] && continue
        [[ "${base}" == "debian.sources" ]] && continue

        _save_original_once "${f}" "${base}"
        _backup_timestamped "${f}" "${base}" >/dev/null
        mv "${f}" "${f}.disabled"
        _manifest_add "third_party" "${f}"
        log_success "Disabled 3rd party repo: ${f}"
        disabled=1
    done
    shopt -u nullglob

    if [[ "${disabled}" -eq 0 ]]; then
        log_info "No active 3rd party repositories found in ${SOURCES_LIST_D}"
    fi
}

repo_action_apt_update() {
    require_root
    log_info "Running apt update..."
    if apt update; then
        log_success "apt update completed"
        return 0
    fi
    log_warn "apt update finished with errors"
    return 1
}

repo_action_restore_all() {
    require_root
    init_iitd_data_dirs

    if [[ ! -d "${IITD_BACKUP_DIR}" ]]; then
        log_error "No backups found at ${IITD_BACKUP_DIR}"
        return 1
    fi

    if ! confirm "Restore all repository files to original state?"; then
        log_info "Cancelled."
        return 0
    fi

    # Restore sources.list
    if [[ -f "${IITD_BACKUP_DIR}/sources.list.original" ]]; then
        cp -a "${IITD_BACKUP_DIR}/sources.list.original" "${SOURCES_LIST}"
        chmod 644 "${SOURCES_LIST}"
        log_success "Restored ${SOURCES_LIST}"
    elif [[ -f "${SOURCES_LIST}" ]]; then
        log_warn "No sources.list.original snapshot — skipped"
    fi

    # Re-enable official DEB822 sources (ubuntu.sources / debian.sources)
    local official_name
    official_name="$(official_sources_filename)"
    if [[ -f "${SOURCES_LIST_D}/${official_name}.disabled" ]]; then
        mv "${SOURCES_LIST_D}/${official_name}.disabled" "${SOURCES_LIST_D}/${official_name}"
        log_success "Re-enabled ${SOURCES_LIST_D}/${official_name}"
    fi
    if [[ -f "${UBUNTU_SOURCES}.disabled" ]]; then
        mv "${UBUNTU_SOURCES}.disabled" "${UBUNTU_SOURCES}"
        log_success "Re-enabled ${UBUNTU_SOURCES}"
    fi
    if [[ -f "${DEBIAN_SOURCES}.disabled" ]]; then
        mv "${DEBIAN_SOURCES}.disabled" "${DEBIAN_SOURCES}"
        log_success "Re-enabled ${DEBIAN_SOURCES}"
    fi

    # Re-enable third party repos from manifest
    if [[ -f "${IITD_REPO_MANIFEST}" ]]; then
        local line key value
        while IFS= read -r line || [[ -n "${line}" ]]; do
            key="${line%%=*}"
            value="${line#*=}"
            if [[ "${key}" == "third_party" && -f "${value}.disabled" ]]; then
                mv "${value}.disabled" "${value}"
                log_success "Re-enabled ${value}"
            fi
        done < "${IITD_REPO_MANIFEST}"
    fi

    # Also restore any .disabled files we may have missed in manifest
    local f
    shopt -s nullglob
    for f in "${SOURCES_LIST_D}"/*.disabled; do
        [[ -f "${f}" ]] || continue
        base="${f%.disabled}"
        if [[ ! -f "${base}" ]]; then
            mv "${f}" "${base}"
            log_success "Re-enabled ${base}"
        fi
    done
    shopt -u nullglob

    if [[ -f "${IITD_REPO_MANIFEST}" ]]; then
        mv "${IITD_REPO_MANIFEST}" "${IITD_REPO_MANIFEST}.restored.$(date +%Y%m%d_%H%M%S)"
    fi

    log_success "Repository restore complete. Backups kept in ${IITD_BACKUP_DIR}"
}
