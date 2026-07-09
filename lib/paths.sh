#!/usr/bin/env bash
# IITD tool system paths and data directories

IITD_ETC_INSTALL="/etc/iitd-tool"
IITD_VAR_LIB="/var/lib/iitd-tool"
IITD_BACKUP_DIR="${IITD_VAR_LIB}/backups"
IITD_STATE_DIR="${IITD_VAR_LIB}/state"
IITD_RUNTIME_CONFIG="${IITD_VAR_LIB}/config"
IITD_REPO_MANIFEST="${IITD_STATE_DIR}/repo.manifest"

init_iitd_data_dirs() {
    mkdir -p "${IITD_BACKUP_DIR}" "${IITD_STATE_DIR}" "${IITD_RUNTIME_CONFIG}"
    chmod 755 "${IITD_VAR_LIB}" "${IITD_BACKUP_DIR}" "${IITD_STATE_DIR}" 2>/dev/null || true
}

is_tool_system_installed() {
    [[ -d "${IITD_ETC_INSTALL}" && -x "${IITD_ETC_INSTALL}/iitd-config" ]]
}

print_iitd_paths_info() {
    echo -e "${BOLD}Data:${NC} ${IITD_VAR_LIB}"
    echo -e "${BOLD}Backups:${NC} ${IITD_BACKUP_DIR}"
    if is_tool_system_installed; then
        echo -e "${BOLD}Install:${NC} ${IITD_ETC_INSTALL}"
    fi
}
