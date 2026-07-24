#!/usr/bin/env bash
# ThingsBoard MQTT telemetry — install / configure / service (Pi 3 & Pi 4)

TB_INSTALL_DIR="/usr/local/lib/iitd-tool/thingsboard"
TB_SCRIPT_DST="${TB_INSTALL_DIR}/thingsboard_telemetry.py"
TB_SCRIPT_SRC="${TOOL_ROOT}/scripts/thingsboard_telemetry.py"
TB_CONF="/etc/iitd-thingsboard.conf"
TB_CONF_TEMPLATE="${TOOL_ROOT}/config/thingsboard/thingsboard.conf.template"
TB_SERVICE_NAME="iitd-thingsboard"
TB_SERVICE_DST="/etc/systemd/system/${TB_SERVICE_NAME}.service"
TB_SERVICE_SRC="${TOOL_ROOT}/config/thingsboard/iitd-thingsboard.service"
TB_PIP_PKG="tb-mqtt-client"

tb_detect_board() {
    if [[ -f /proc/device-tree/model ]]; then
        tr -d '\0' < /proc/device-tree/model
        return 0
    fi
    echo "generic-linux"
}

tb_prompt_nonempty() {
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

tb_conf_get() {
    local key="$1"
    local conf="${2:-${TB_CONF}}"
    [[ -f "${conf}" ]] || return 1
    grep -E "^[[:space:]]*${key}=" "${conf}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tb_write_conf() {
    local host="$1"
    local port="$2"
    local token="$3"
    local interval="$4"
    local name="$5"

    init_iitd_data_dirs
    if [[ -f "${TB_CONF}" ]]; then
        _save_original_once "${TB_CONF}" "iitd-thingsboard.conf" 2>/dev/null || true
        _backup_timestamped "${TB_CONF}" "iitd-thingsboard.conf" >/dev/null 2>&1 || true
    fi

    cat > "${TB_CONF}" <<EOF
# Managed by IITD Lab Setup Tool — ThingsBoard telemetry
TB_HOST=${host}
TB_PORT=${port}
TB_ACCESS_TOKEN=${token}
TB_INTERVAL=${interval}
TB_DEVICE_NAME=${name}
EOF
    chmod 600 "${TB_CONF}"
    log_success "Wrote ${TB_CONF} (mode 600)"
}

tb_install_python_deps() {
    # Prefer system python3; Pi 3 / older Debian need pip3
    if ! command -v python3 >/dev/null 2>&1; then
        log_info "Installing python3..."
        apt-get update -qq || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3 || return 1
    fi

    if ! command -v pip3 >/dev/null 2>&1; then
        log_info "Installing python3-pip..."
        apt-get update -qq || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip || return 1
    fi

    # Pi 3: ensure openssl / ca certs for MQTT TLS if used later
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-setuptools ca-certificates 2>/dev/null || true

    log_info "Installing Python package: ${TB_PIP_PKG} (ThingsBoard MQTT SDK)..."
    # --break-system-packages for newer Debian/Ubuntu; ignore flag on older pip
    if pip3 install --upgrade "${TB_PIP_PKG}" 2>/dev/null; then
        log_success "pip installed ${TB_PIP_PKG}"
    elif pip3 install --break-system-packages --upgrade "${TB_PIP_PKG}"; then
        log_success "pip installed ${TB_PIP_PKG} (--break-system-packages)"
    else
        log_error "Failed to install ${TB_PIP_PKG}"
        log_info "Campus? Enable proxy: iitd-proxy <role> <userid>"
        return 1
    fi

    if ! python3 -c "from tb_gateway_mqtt import TBDeviceMqttClient" 2>/dev/null; then
        log_error "Import check failed: tb_gateway_mqtt.TBDeviceMqttClient"
        return 1
    fi
    log_success "Import OK: TBDeviceMqttClient"
}

tb_install() {
    require_root

    local board
    board="$(tb_detect_board)"
    echo
    echo -e "${BOLD}Install ThingsBoard telemetry${NC}"
    echo
    echo "  Board:   ${board}"
    echo "  Script:  ${TB_SCRIPT_DST}"
    echo "  Service: ${TB_SERVICE_NAME}"
    echo "  Target:  Raspberry Pi 3 / Pi 4 / Debian-Ubuntu"
    echo

    if ! confirm "Install ThingsBoard client + systemd service?"; then
        log_info "Cancelled."
        return 0
    fi

    if ! tb_install_python_deps; then
        return 1
    fi

    mkdir -p "${TB_INSTALL_DIR}"
    install -m 0755 "${TB_SCRIPT_SRC}" "${TB_SCRIPT_DST}"
    install -m 0644 "${TB_SERVICE_SRC}" "${TB_SERVICE_DST}"

    if [[ ! -f "${TB_CONF}" ]]; then
        install -m 0600 "${TB_CONF_TEMPLATE}" "${TB_CONF}"
        log_info "Default config created: ${TB_CONF} — set ACCESS_TOKEN next"
    fi

    systemctl daemon-reload
    log_success "Installed ThingsBoard telemetry files"
    echo
    log_info "Next: Configure (token + server) → Enable & start service"
}

tb_configure() {
    require_root

    echo
    echo -e "${BOLD}Configure ThingsBoard${NC}"
    echo

    if [[ ! -f "${TB_SCRIPT_DST}" ]]; then
        log_warn "Client not installed yet"
        if confirm "Install first?"; then
            tb_install || return 1
        else
            return 0
        fi
    fi

    local host port token interval name
    host="$(tb_conf_get TB_HOST 2>/dev/null || true)"
    port="$(tb_conf_get TB_PORT 2>/dev/null || true)"
    token="$(tb_conf_get TB_ACCESS_TOKEN 2>/dev/null || true)"
    interval="$(tb_conf_get TB_INTERVAL 2>/dev/null || true)"
    name="$(tb_conf_get TB_DEVICE_NAME 2>/dev/null || true)"

    [[ -z "${host}" || "${host}" == "thingsboard.ipserver.in" ]] && host="thingsboard.ipserver.in"
    [[ -z "${port}" ]] && port="1883"
    [[ -z "${interval}" || "${interval}" == "CHANGE_ME" ]] && interval="30"
    [[ "${token}" == "CHANGE_ME" ]] && token=""

    host="$(tb_prompt_nonempty "ThingsBoard host" "${host}")"
    port="$(tb_prompt_nonempty "MQTT port" "${port}")"
    token="$(tb_prompt_nonempty "Device ACCESS_TOKEN" "${token}")"
    interval="$(tb_prompt_nonempty "Telemetry interval (seconds, min 10)" "${interval}")"
    read -r -p "Device name label (optional) [${name}]: " name_in
    name="${name_in:-${name}}"

    if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        log_error "Port must be a number"
        return 1
    fi
    if ! [[ "${interval}" =~ ^[0-9]+$ ]] || (( interval < 10 )); then
        log_warn "Interval too low for Pi 3 — using 30"
        interval=30
    fi

    echo
    echo "Preview:"
    echo "  Host:     ${host}:${port}"
    echo "  Token:    ${token:0:4}… (${#token} chars)"
    echo "  Interval: ${interval}s"
    echo "  Name:     ${name:-"(none)"}"
    echo

    if ! confirm "Save configuration?"; then
        log_info "Cancelled."
        return 0
    fi

    tb_write_conf "${host}" "${port}" "${token}" "${interval}" "${name}"

    if systemctl is-enabled --quiet "${TB_SERVICE_NAME}" 2>/dev/null \
        || systemctl is-active --quiet "${TB_SERVICE_NAME}" 2>/dev/null; then
        if confirm "Restart ${TB_SERVICE_NAME} to apply config?"; then
            systemctl restart "${TB_SERVICE_NAME}" || log_warn "Restart failed"
        fi
    fi
}

tb_enable_start() {
    require_root

    if [[ ! -f "${TB_SCRIPT_DST}" || ! -f "${TB_SERVICE_DST}" ]]; then
        log_error "Not installed. Run Install first."
        return 1
    fi

    local token
    token="$(tb_conf_get TB_ACCESS_TOKEN 2>/dev/null || true)"
    if [[ -z "${token}" || "${token}" == "CHANGE_ME" ]]; then
        log_error "ACCESS_TOKEN not set. Run Configure first."
        return 1
    fi

    if ! confirm "Enable and start ${TB_SERVICE_NAME}?"; then
        log_info "Cancelled."
        return 0
    fi

    systemctl daemon-reload
    systemctl enable "${TB_SERVICE_NAME}"
    systemctl restart "${TB_SERVICE_NAME}"
    sleep 1
    if systemctl is-active --quiet "${TB_SERVICE_NAME}"; then
        log_success "Service active — telemetry sending to ThingsBoard"
    else
        log_error "Service failed — check: journalctl -u ${TB_SERVICE_NAME} -n 50"
        return 1
    fi
}

tb_stop() {
    require_root
    if ! systemctl list-unit-files 2>/dev/null | grep -q "${TB_SERVICE_NAME}"; then
        log_info "Service not installed"
        return 0
    fi
    if ! confirm "Stop ${TB_SERVICE_NAME}?"; then
        log_info "Cancelled."
        return 0
    fi
    systemctl stop "${TB_SERVICE_NAME}" || true
    log_success "Service stopped"
}

tb_status() {
    echo
    echo -e "${BOLD}ThingsBoard telemetry status${NC}"
    echo
    echo -e "${BOLD}Board:${NC} $(tb_detect_board)"
    if [[ -f "${TB_SCRIPT_DST}" ]]; then
        log_success "Script: ${TB_SCRIPT_DST}"
    else
        log_warn "Script not installed"
    fi
    if [[ -f "${TB_CONF}" ]]; then
        echo -e "${BOLD}Config:${NC} ${TB_CONF}"
        echo "  Host:     $(tb_conf_get TB_HOST 2>/dev/null || echo '?')"
        echo "  Port:     $(tb_conf_get TB_PORT 2>/dev/null || echo '?')"
        local tok
        tok="$(tb_conf_get TB_ACCESS_TOKEN 2>/dev/null || true)"
        if [[ -n "${tok}" && "${tok}" != "CHANGE_ME" ]]; then
            echo "  Token:    ${tok:0:4}… set"
        else
            echo "  Token:    NOT SET"
        fi
        echo "  Interval: $(tb_conf_get TB_INTERVAL 2>/dev/null || echo '?')s"
    else
        log_warn "Config missing: ${TB_CONF}"
    fi
    echo
    if command -v systemctl >/dev/null 2>&1 && [[ -f "${TB_SERVICE_DST}" ]]; then
        systemctl status "${TB_SERVICE_NAME}" --no-pager -l | head -n 20 || true
    fi
    echo
}

tb_remove() {
    require_root

    echo
    echo -e "${BOLD}Remove ThingsBoard telemetry${NC}"
    echo "Stops service, removes script/unit. Config backup kept in ${IITD_BACKUP_DIR}."
    echo
    if ! confirm "Remove ThingsBoard client from this system?"; then
        log_info "Cancelled."
        return 0
    fi

    systemctl stop "${TB_SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${TB_SERVICE_NAME}" 2>/dev/null || true
    rm -f "${TB_SERVICE_DST}"
    systemctl daemon-reload 2>/dev/null || true
    rm -rf "${TB_INSTALL_DIR}"

    if [[ -f "${TB_CONF}" ]]; then
        init_iitd_data_dirs
        _backup_timestamped "${TB_CONF}" "iitd-thingsboard.conf" >/dev/null 2>&1 || true
        if confirm "Also delete ${TB_CONF}?"; then
            rm -f "${TB_CONF}"
            log_info "Config deleted"
        else
            log_info "Config kept: ${TB_CONF}"
        fi
    fi

    log_success "ThingsBoard telemetry removed"
}

show_thingsboard_submenu() {
    clear
    echo -e "${BOLD}${CYAN}ThingsBoard Telemetry${NC}"
    echo
    print_system_info
    echo -e "${BOLD}Board:${NC} $(tb_detect_board)"
    if systemctl is-active --quiet "${TB_SERVICE_NAME}" 2>/dev/null; then
        echo -e "${BOLD}Service:${NC} ${GREEN}active${NC}"
    elif [[ -f "${TB_SERVICE_DST}" ]]; then
        echo -e "${BOLD}Service:${NC} ${YELLOW}installed (stopped)${NC}"
    else
        echo -e "${BOLD}Service:${NC} ${YELLOW}not installed${NC}"
    fi
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Install client (Python SDK + script + systemd)"
    echo "  2) Configure (host / token / interval)"
    echo "  3) Enable & start service"
    echo "  4) Stop service"
    echo "  5) Show status / logs hint"
    echo "  6) Remove ThingsBoard client"
    echo
    echo "  Tip: Pi 3 — interval >= 30s recommended"
    echo
    echo "  b) Back to main menu"
    echo
}

run_thingsboard_menu() {
    local choice
    while true; do
        show_thingsboard_submenu
        read -r -p "Select option [1-6, b]: " choice
        case "${choice}" in
            1) tb_install || true; pause ;;
            2) tb_configure || true; pause ;;
            3) tb_enable_start || true; pause ;;
            4) tb_stop || true; pause ;;
            5) tb_status; pause ;;
            6) tb_remove || true; pause ;;
            b|B|q|Q) break ;;
            *) log_warn "Invalid choice: ${choice}"; pause ;;
        esac
    done
}
