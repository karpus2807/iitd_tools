#!/usr/bin/env bash
# Proxy module — installs iitd-proxy command on the system (one-time).
# After install, users run: sudo iitd-proxy <role> <userid>

MODULE_ID="proxy"
MODULE_NAME="Proxy Setup (Install iitd-proxy)"
MODULE_DESCRIPTION="Install iitd-proxy command for system-wide IITD proxy enable/logout"
MODULE_ORDER=20

INSTALL_DIR="/usr/local/lib/iitd-tool"
INSTALL_BIN="/usr/local/bin/iitd-proxy"
SOURCE_LAUNCHER="${TOOL_ROOT}/scripts/iitd-proxy"
SOURCE_PY="${TOOL_ROOT}/scripts/iitd-proxy.py"

module_supported_versions() {
    echo "all"
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_dependencies() {
    # shellcheck source=lib/python.sh
    source "${TOOL_ROOT}/lib/python.sh"

    if ! detect_python; then
        return 1
    fi

    local py_pkg
    py_pkg="$(python_package_name)"

    local missing=()
    local pkg

    for pkg in "${py_pkg}" ca-certificates; do
        if ! package_installed "${pkg}"; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_info "Required packages already installed (${PYTHON_CMD}, ca-certificates)."
        return 0
    fi

    log_info "Detected Python: ${PYTHON_CMD} (${PYTHON_VERSION})"
    log_info "Installing required packages: ${missing[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

install_iitd_proxy() {
    if [[ ! -f "${SOURCE_LAUNCHER}" ]] || [[ ! -f "${SOURCE_PY}" ]]; then
        log_error "iitd-proxy files not found under ${TOOL_ROOT}/scripts/"
        return 1
    fi

    mkdir -p "${INSTALL_DIR}"
    install -m 0755 "${SOURCE_LAUNCHER}" "${INSTALL_BIN}"
    install -m 0644 "${SOURCE_PY}" "${INSTALL_DIR}/iitd-proxy.py"
    install -m 0644 "${TOOL_ROOT}/lib/python.sh" "${INSTALL_DIR}/python.sh"

    log_success "Installed ${INSTALL_BIN}"
    log_success "Installed ${INSTALL_DIR}/iitd-proxy.py"
    log_success "Installed ${INSTALL_DIR}/python.sh"
}

show_usage() {
    # shellcheck source=lib/python.sh
    source "${TOOL_ROOT}/lib/python.sh"
    detect_python 2>/dev/null || true

    echo
    echo -e "${BOLD}Usage after install:${NC}"
    echo "  sudo iitd-proxy <role> <userid>    # enable proxy system-wide"
    echo "  sudo iitd-proxy logout             # remove proxy from system"
    echo
    echo -e "${BOLD}Roles:${NC} btech, mtech, phd, staff, faculty, visitor"
    if [[ -n "${PYTHON_CMD:-}" ]]; then
        echo -e "${BOLD}Python:${NC} ${PYTHON_CMD} (${PYTHON_VERSION}, system /usr/bin)"
    fi
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo "  sudo iitd-proxy staff krajaymeena"
    echo "  sudo iitd-proxy phd ankit"
    echo "  sudo iitd-proxy logout"
    echo
    echo "Proxy applies to: apt, snap, GNOME GUI, wget, curl, Chrome, Chromium, Firefox"
    echo "Run the enable command again anytime to switch role or user."
}

module_run() {
    # shellcheck source=lib/python.sh
    source "${TOOL_ROOT}/lib/python.sh"

    echo "This will install the ${BOLD}iitd-proxy${NC} command on this system."
    echo
    echo "  Install path: ${INSTALL_BIN}"
    echo "  Python lib:   ${INSTALL_DIR}/iitd-proxy.py"
    echo

    if detect_python; then
        echo -e "  Detected:     ${BOLD}${PYTHON_CMD}${NC} (${PYTHON_VERSION}, system)"
        echo "  Policy:       only /usr/bin python3/python2 — custom installs ignored"
    else
        log_warn "Python not found yet — install will try to add python3 or python-minimal."
    fi
    echo
    echo "After install, proxy is enabled separately with:"
    echo "  sudo iitd-proxy <role> <userid>"
    echo

    if [[ -x "${INSTALL_BIN}" ]] && [[ -f "${INSTALL_DIR}/iitd-proxy.py" ]]; then
        log_warn "iitd-proxy is already installed at ${INSTALL_BIN}"
        if ! confirm "Reinstall / update iitd-proxy?"; then
            show_usage
            return 0
        fi
    else
        if ! confirm "Proceed with iitd-proxy installation?"; then
            log_info "Cancelled."
            return 0
        fi
    fi

    require_root

    if ! install_dependencies; then
        log_error "Failed to install required packages."
        return 1
    fi

    if ! install_iitd_proxy; then
        return 1
    fi

    if ! "${INSTALL_BIN}" --help >/dev/null 2>&1; then
        log_warn "Installed, but help check failed — verify ${INSTALL_BIN} manually."
    fi

    log_success "iitd-proxy installation complete!"
    show_usage
}
