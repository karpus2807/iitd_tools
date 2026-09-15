#!/usr/bin/env bash
# Proxy module — installs iitd-proxy CLI (no sudoers / no NOPASSWD).
# System-wide proxy is enabled by sudo iitd-tool (staff login at startup).
# Any user may run iitd-proxy for login + user-session settings (no root).

MODULE_ID="proxy"
MODULE_NAME="Proxy Setup (Install iitd-proxy)"
MODULE_DESCRIPTION="Install iitd-proxy CLI — users need no sudo; system proxy via iitd-tool"
MODULE_ORDER=20

INSTALL_DIR="/usr/local/lib/iitd-tool"
INSTALL_BIN="/usr/local/bin/iitd-proxy"
SOURCE_LAUNCHER="${TOOL_ROOT}/scripts/iitd-proxy"
SOURCE_PY="${TOOL_ROOT}/scripts/iitd-proxy.py"
SUDOERS_DEST="/etc/sudoers.d/iitd-proxy"

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

remove_legacy_iitd_ca_certificate() {
    local removed=0
    local f

    for f in \
        "/usr/local/share/ca-certificates/iitd-cciitd-ca.crt" \
        "/usr/local/lib/iitd-tool/certs/CCIITD-CA.crt"; do
        if [[ -f "${f}" ]]; then
            rm -f "${f}"
            log_info "Removed legacy IITD CA certificate: ${f}"
            removed=1
        fi
    done

    if [[ -d "${INSTALL_DIR}/certs" ]] && [[ ! -e "${INSTALL_DIR}/certs/ca-chain.crt" ]]; then
        rmdir "${INSTALL_DIR}/certs" 2>/dev/null || true
    fi

    if [[ "${removed}" -eq 1 ]] && command -v update-ca-certificates >/dev/null 2>&1; then
        update-ca-certificates
        log_info "Refreshed system CA trust store"
    fi
}

remove_legacy_proxy_sudoers() {
    if [[ -e "${SUDOERS_DEST}" ]]; then
        rm -f "${SUDOERS_DEST}"
        log_success "Removed legacy passwordless sudoers: ${SUDOERS_DEST}"
        log_info "iitd-proxy no longer grants sudo to any user."
    fi
}

install_iitd_proxy() {
    if [[ ! -f "${SOURCE_LAUNCHER}" ]] || [[ ! -f "${SOURCE_PY}" ]]; then
        log_error "iitd-proxy files not found under ${TOOL_ROOT}/scripts/"
        return 1
    fi

    mkdir -p "${INSTALL_DIR}"
    remove_legacy_iitd_ca_certificate
    remove_legacy_proxy_sudoers
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
    echo -e "${BOLD}Usage (no sudo — any user):${NC}"
    echo "  iitd-proxy <role> <userid>    # IITD login + user-session proxy"
    echo "  iitd-proxy logout             # clear user-session proxy (and system if root)"
    echo "  iitd-proxy shell              # interactive login"
    echo
    echo -e "${BOLD}System-wide apt/snap/docker/browsers:${NC}"
    echo "  sudo iitd-tool                # staff login at startup configures everything"
    echo
    echo -e "${BOLD}Roles:${NC} btech, mtech, phd, staff, faculty, visitor"
    if [[ -n "${PYTHON_CMD:-}" ]]; then
        echo -e "${BOLD}Python:${NC} ${PYTHON_CMD} (${PYTHON_VERSION}, system /usr/bin)"
    fi
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo "  iitd-proxy staff krajaymeena"
    echo "  iitd-proxy phd ankit"
    echo "  iitd-proxy logout"
    echo
    echo "No passwordless sudoers. Proxy CLI never elevates to root."
    echo "HTTPS login uses verified TLS (set IITD_PROXY_INSECURE_TLS=1 only if needed)."
    echo "Docker: daemon drop-in + ~/.docker/config.json (system-wide via sudo iitd-tool)."
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
    echo "After install:"
    echo "  • Any user: iitd-proxy <role> <userid>  (no sudo, no root)"
    echo "  • Admin:    sudo iitd-tool  → staff proxy at startup (system-wide)"
    echo "  • Removes any old /etc/sudoers.d/iitd-proxy rule"
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
