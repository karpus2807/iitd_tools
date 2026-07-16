#!/usr/bin/env bash
# SNMP install / configure / remove helpers

SNMP_CONF="/etc/snmp/snmpd.conf"
SNMP_TEMPLATE="${TOOL_ROOT}/config/snmp/snmpd.conf.template"
SNMP_PACKAGES=(snmpd snmp)
SNMP_SERVICE="snmpd"

snmp_package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

snmp_is_installed() {
    snmp_package_installed snmpd
}

snmp_install_from_apt() {
    require_root

    echo
    echo -e "${BOLD}Install SNMP (apt)${NC}"
    echo
    echo "Packages: ${SNMP_PACKAGES[*]}"
    echo

    if snmp_is_installed; then
        log_warn "snmpd is already installed"
        if ! confirm "Reinstall / update snmp packages?"; then
            log_info "Cancelled."
            return 0
        fi
    else
        if ! confirm "Install SNMP packages now?"; then
            log_info "Cancelled."
            return 0
        fi
    fi

    log_info "Running apt-get update..."
    apt-get update -qq || log_warn "apt-get update had issues — continuing"

    if DEBIAN_FRONTEND=noninteractive apt-get install -y "${SNMP_PACKAGES[@]}"; then
        log_success "Installed: ${SNMP_PACKAGES[*]}"
    else
        log_error "Failed to install SNMP packages"
        log_info "On campus, enable proxy first: iitd-proxy <role> <userid>"
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable "${SNMP_SERVICE}" >/dev/null 2>&1 || true
        systemctl restart "${SNMP_SERVICE}" >/dev/null 2>&1 || true
        systemctl is-active --quiet "${SNMP_SERVICE}" \
            && log_success "Service ${SNMP_SERVICE}: active" \
            || log_warn "Service ${SNMP_SERVICE}: not active yet (configure SNMP next)"
    fi

    echo
    log_info "Next: submenu → Config SNMP (asks for Location + Contact)"
}

snmp_prompt_nonempty() {
    local prompt="$1"
    local default="${2:-}"
    local value=""

    while true; do
        if [[ -n "${default}" ]]; then
            read -r -p "${prompt} [${default}]: " value
            value="${value:-${default}}"
        else
            read -r -p "${prompt}: " value
        fi
        value="$(echo "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -n "${value}" ]]; then
            echo "${value}"
            return 0
        fi
        log_warn "Value cannot be empty"
    done
}

snmp_write_config() {
    local location="$1"
    local contact="$2"
    local tmp

    if [[ ! -f "${SNMP_TEMPLATE}" ]]; then
        log_error "Template missing: ${SNMP_TEMPLATE}"
        return 1
    fi

    mkdir -p "$(dirname "${SNMP_CONF}")"
    init_iitd_data_dirs

    # Preserve original once before first tool-managed write
    if [[ -f "${SNMP_CONF}" ]]; then
        _save_original_once "${SNMP_CONF}" "snmpd.conf"
        _backup_timestamped "${SNMP_CONF}" "snmpd.conf" >/dev/null
    fi

    tmp="$(mktemp)"
    # Escape & for sed replacements
    local loc_esc contact_esc
    loc_esc="$(printf '%s' "${location}" | sed -e 's/[&\\/]/\\&/g')"
    contact_esc="$(printf '%s' "${contact}" | sed -e 's/[&\\/]/\\&/g')"

    sed \
        -e "s/<sysLocation>/${loc_esc}/g" \
        -e "s/<sysContact>/${contact_esc}/g" \
        "${SNMP_TEMPLATE}" > "${tmp}"

    install -m 0644 "${tmp}" "${SNMP_CONF}"
    rm -f "${tmp}"
    log_success "Wrote ${SNMP_CONF}"
}

snmp_config() {
    require_root

    echo
    echo -e "${BOLD}Config SNMP${NC}"
    echo
    echo "SNMPv2c template will be applied."
    echo "Fixed: community cse!005 @ 10.208.20.30 , UDP 161, system views, DMI extends"
    echo
    echo "You will enter (changes per machine):"
    echo "  - sysLocation"
    echo "  - sysContact"
    echo

    if ! snmp_is_installed; then
        log_warn "snmpd is not installed"
        if confirm "Install SNMP packages first?"; then
            snmp_install_from_apt || return 1
        else
            log_info "Cancelled."
            return 0
        fi
    fi

    local location contact
    location="$(snmp_prompt_nonempty "sysLocation (e.g. SIT411 - CSE)")"
    contact="$(snmp_prompt_nonempty "sysContact (e.g. user@cse.iitd.ac.in)")"

    echo
    echo "Preview:"
    echo "  sysLocation    ${location}"
    echo "  sysContact     ${contact}"
    echo

    if ! confirm "Write SNMP config and restart snmpd?"; then
        log_info "Cancelled."
        return 0
    fi

    if ! snmp_write_config "${location}" "${contact}"; then
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable "${SNMP_SERVICE}" >/dev/null 2>&1 || true
        if systemctl restart "${SNMP_SERVICE}"; then
            log_success "Restarted ${SNMP_SERVICE}"
        else
            log_error "Failed to restart ${SNMP_SERVICE} — check: journalctl -u snmpd"
            return 1
        fi
        systemctl is-active --quiet "${SNMP_SERVICE}" \
            && log_success "snmpd is active" \
            || log_warn "snmpd not active"
    else
        service snmpd restart 2>/dev/null || true
    fi

    echo
    log_info "Test from monitor host (example):"
    echo "  snmpwalk -v2c -c 'cse!005' <this-host-ip> system"
}

snmp_remove_config() {
    require_root

    echo
    echo -e "${BOLD}Remove SNMP config${NC}"
    echo
    echo "This restores previous/original snmpd.conf if available,"
    echo "or reinstalls the package default config."
    echo

    if [[ ! -f "${SNMP_CONF}" ]]; then
        log_info "No ${SNMP_CONF} present"
        return 0
    fi

    if ! confirm "Remove / restore SNMP config now?"; then
        log_info "Cancelled."
        return 0
    fi

    init_iitd_data_dirs
    _backup_timestamped "${SNMP_CONF}" "snmpd.conf" >/dev/null

    local original="${IITD_BACKUP_DIR}/snmpd.conf.original"
    if [[ -f "${original}" ]]; then
        cp -a "${original}" "${SNMP_CONF}"
        chmod 644 "${SNMP_CONF}"
        log_success "Restored original: ${original}"
    elif snmp_is_installed; then
        log_info "Reinstalling package default snmpd.conf..."
        DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y \
            -o Dpkg::Options::="--force-confmiss" \
            -o Dpkg::Options::="--force-confnew" \
            snmpd || log_warn "apt reinstall had issues"
        if [[ ! -f "${SNMP_CONF}" ]]; then
            log_warn "snmpd.conf still missing after reinstall"
        else
            log_success "Package default config restored (if available)"
        fi
    else
        rm -f "${SNMP_CONF}"
        log_success "Removed ${SNMP_CONF}"
    fi

    if command -v systemctl >/dev/null 2>&1 && snmp_is_installed; then
        systemctl restart "${SNMP_SERVICE}" >/dev/null 2>&1 || true
    fi
}

snmp_remove_tool() {
    require_root

    echo
    echo -e "${BOLD}Remove SNMP tool${NC}"
    echo
    echo "Will purge packages: ${SNMP_PACKAGES[*]}"
    echo "Config under ${SNMP_CONF} may also be removed (purge)."
    echo "Tool backups in ${IITD_BACKUP_DIR} are kept."
    echo

    if ! snmp_is_installed && ! snmp_package_installed snmp; then
        log_info "SNMP packages are not installed"
        return 0
    fi

    if ! confirm "Purge SNMP packages from this system?"; then
        log_info "Cancelled."
        return 0
    fi

    if [[ -f "${SNMP_CONF}" ]]; then
        init_iitd_data_dirs
        _backup_timestamped "${SNMP_CONF}" "snmpd.conf" >/dev/null
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "${SNMP_SERVICE}" >/dev/null 2>&1 || true
        systemctl disable "${SNMP_SERVICE}" >/dev/null 2>&1 || true
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get purge -y "${SNMP_PACKAGES[@]}"; then
        log_success "Purged: ${SNMP_PACKAGES[*]}"
    else
        log_error "Failed to purge SNMP packages"
        return 1
    fi

    apt-get autoremove -y >/dev/null 2>&1 || true
    log_success "SNMP tool removed"
}

show_snmp_submenu() {
    clear
    echo -e "${BOLD}${CYAN}SNMP Setup${NC}"
    echo
    print_system_info
    echo -e "${BOLD}Config file:${NC} ${SNMP_CONF}"
    if snmp_is_installed; then
        echo -e "${BOLD}Package:${NC} ${GREEN}snmpd installed${NC}"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet "${SNMP_SERVICE}" 2>/dev/null; then
                echo -e "${BOLD}Service:${NC} ${GREEN}active${NC}"
            else
                echo -e "${BOLD}Service:${NC} ${YELLOW}inactive${NC}"
            fi
        fi
    else
        echo -e "${BOLD}Package:${NC} ${YELLOW}not installed${NC}"
    fi
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Install SNMP from apt"
    echo "  2) Config SNMP (asks Location + Contact)"
    echo "  3) Remove SNMP config"
    echo "  4) Remove SNMP tool"
    echo
    echo "  b) Back to main menu"
    echo
}

run_snmp_menu() {
    local choice

    while true; do
        show_snmp_submenu
        read -r -p "Select option [1-4, b]: " choice

        case "${choice}" in
            1)
                snmp_install_from_apt || true
                pause
                ;;
            2)
                snmp_config || true
                pause
                ;;
            3)
                snmp_remove_config || true
                pause
                ;;
            4)
                snmp_remove_tool || true
                pause
                ;;
            b|B|q|Q)
                break
                ;;
            *)
                log_warn "Invalid choice: ${choice}"
                pause
                ;;
        esac
    done
}
