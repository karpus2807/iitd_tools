#!/usr/bin/env bash
# System-wide installation of IITD tool

IITD_BIN_LINK="/usr/local/bin/iitd-tool"
IITD_CONFIG_LINK="/usr/local/bin/iitd-config"

_install_copy_tree() {
    local src="$1"
    local dest="$2"

    mkdir -p "${dest}"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude '.git' --exclude '__pycache__' "${src}/" "${dest}/"
    else
        cp -a "${src}/." "${dest}/"
        rm -rf "${dest}/.git" "${dest}/__pycache__" 2>/dev/null || true
    fi
}

install_iitd_tool_system() {
    require_root

    local auto_yes=0
    if [[ "${IITD_INSTALL_YES:-0}" == "1" ]]; then
        auto_yes=1
    fi

    echo
    echo -e "${BOLD}IITD Tool — System Install${NC}"
    echo
    echo "  Install to:  ${IITD_ETC_INSTALL}"
    echo "  Data dir:    ${IITD_VAR_LIB}"
    echo "  Commands:    ${IITD_BIN_LINK}"
    echo "               ${IITD_CONFIG_LINK}"
    echo

    if is_tool_system_installed; then
        log_warn "Tool already installed at ${IITD_ETC_INSTALL}"
        if [[ "${auto_yes}" -eq 0 ]]; then
            if ! confirm "Reinstall / update system copy?"; then
                return 0
            fi
        else
            log_info "Updating system copy from ${TOOL_ROOT}..."
        fi
    else
        if [[ "${auto_yes}" -eq 0 ]]; then
            if ! confirm "Install IITD tool system-wide?"; then
                log_info "Cancelled."
                return 0
            fi
        fi
    fi

    log_info "Copying tool files..."
    _install_copy_tree "${TOOL_ROOT}" "${IITD_ETC_INSTALL}"

    chmod +x "${IITD_ETC_INSTALL}/iitd-config" "${IITD_ETC_INSTALL}/iitd-tool" 2>/dev/null || true
    chmod +x "${IITD_ETC_INSTALL}/scripts/iitd-proxy" 2>/dev/null || true

    ln -sf "${IITD_ETC_INSTALL}/iitd-tool" "${IITD_BIN_LINK}"
    ln -sf "${IITD_ETC_INSTALL}/iitd-config" "${IITD_CONFIG_LINK}"

    init_iitd_data_dirs

    log_success "IITD tool installed system-wide."
    echo
    echo "Run from anywhere:"
    echo "  sudo iitd-tool"
    echo "  sudo iitd-config"
    echo
    echo "Data & backups: ${IITD_VAR_LIB}"
}

uninstall_iitd_tool_system() {
    require_root

    echo
    echo -e "${BOLD}IITD Tool — System Uninstall${NC}"
    echo

    if ! is_tool_system_installed; then
        log_warn "Tool is not installed at ${IITD_ETC_INSTALL}"
        return 0
    fi

    echo "Will remove:"
    echo "  ${IITD_ETC_INSTALL}"
    echo "  ${IITD_BIN_LINK}"
    echo "  ${IITD_CONFIG_LINK}"
    echo

    if ! confirm "Uninstall IITD tool from this system?"; then
        log_info "Cancelled."
        return 0
    fi

    local remove_data=0
    if [[ -d "${IITD_VAR_LIB}" ]]; then
        echo
        echo "Data directory: ${IITD_VAR_LIB}"
        if confirm "Also delete backups and state data?"; then
            remove_data=1
        else
            log_info "Data will be kept at ${IITD_VAR_LIB}"
        fi
    fi

    rm -f "${IITD_BIN_LINK}" "${IITD_CONFIG_LINK}"
    rm -rf "${IITD_ETC_INSTALL}"

    if [[ "${remove_data}" -eq 1 ]]; then
        rm -rf "${IITD_VAR_LIB}"
        log_info "Removed ${IITD_VAR_LIB}"
    fi

    log_success "IITD tool uninstalled."
    echo
    log_info "Note: iitd-proxy (if installed separately) is not removed."
    if [[ "${remove_data}" -eq 0 && -d "${IITD_VAR_LIB}" ]]; then
        echo "Backups preserved: ${IITD_VAR_LIB}"
    fi
}

show_tool_install_status() {
    echo
    if is_tool_system_installed; then
        log_success "Installed at ${IITD_ETC_INSTALL}"
        echo "  Command: ${IITD_BIN_LINK}"
        echo "  Data:    ${IITD_VAR_LIB}"
    else
        log_warn "Not installed system-wide (running from ${TOOL_ROOT})"
        echo "  Use menu option: Install tool system-wide"
    fi
}
