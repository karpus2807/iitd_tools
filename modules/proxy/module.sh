#!/usr/bin/env bash
# Proxy module — installs iitd-proxy command on the system (one-time).
# After install, any user runs: iitd-proxy <role> <userid>  (no sudo typed)

MODULE_ID="proxy"
MODULE_NAME="Proxy Setup (Install iitd-proxy)"
MODULE_DESCRIPTION="Install iitd-proxy — then any user can login/logout without sudo"
MODULE_ORDER=20

INSTALL_DIR="/usr/local/lib/iitd-tool"
INSTALL_BIN="/usr/local/bin/iitd-proxy"
SOURCE_LAUNCHER="${TOOL_ROOT}/scripts/iitd-proxy"
SOURCE_PY="${TOOL_ROOT}/scripts/iitd-proxy.py"
SOURCE_SUDOERS="${TOOL_ROOT}/config/sudoers.iitd-proxy"
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

    rmdir "${INSTALL_DIR}/certs" 2>/dev/null || true

    if [[ "${removed}" -eq 1 ]] && command -v update-ca-certificates >/dev/null 2>&1; then
        update-ca-certificates
        log_info "Refreshed system CA trust store"
    fi
}

install_iitd_proxy_sudoers() {
    if [[ ! -f "${SOURCE_SUDOERS}" ]]; then
        log_warn "sudoers template missing: ${SOURCE_SUDOERS}"
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    cp "${SOURCE_SUDOERS}" "${tmp}"
    chmod 440 "${tmp}"

    if command -v visudo >/dev/null 2>&1; then
        if ! visudo -cf "${tmp}" >/dev/null 2>&1; then
            log_error "Invalid sudoers template — not installing ${SUDOERS_DEST}"
            rm -f "${tmp}"
            return 1
        fi
    fi

    install -m 0440 "${tmp}" "${SUDOERS_DEST}"
    rm -f "${tmp}"

    if command -v visudo >/dev/null 2>&1 && ! visudo -cf "${SUDOERS_DEST}" >/dev/null 2>&1; then
        log_error "Installed sudoers failed validation — removing ${SUDOERS_DEST}"
        rm -f "${SUDOERS_DEST}"
        return 1
    fi

    log_success "Installed passwordless rule: ${SUDOERS_DEST}"
    log_info "Any user can now run: iitd-proxy <role> <userid>  (no sudo password)"
}

install_iitd_proxy() {
    if [[ ! -f "${SOURCE_LAUNCHER}" ]] || [[ ! -f "${SOURCE_PY}" ]]; then
        log_error "iitd-proxy files not found under ${TOOL_ROOT}/scripts/"
        return 1
    fi

    mkdir -p "${INSTALL_DIR}"
    remove_legacy_iitd_ca_certificate
    install -m 0755 "${SOURCE_LAUNCHER}" "${INSTALL_BIN}"
    install -m 0644 "${SOURCE_PY}" "${INSTALL_DIR}/iitd-proxy.py"
    install -m 0644 "${TOOL_ROOT}/lib/python.sh" "${INSTALL_DIR}/python.sh"

    install_iitd_proxy_sudoers || log_warn "sudoers not installed — users may still need sudo password"

    log_success "Installed ${INSTALL_BIN}"
    log_success "Installed ${INSTALL_DIR}/iitd-proxy.py"
    log_success "Installed ${INSTALL_DIR}/python.sh"
}

show_usage() {
    # shellcheck source=lib/python.sh
    source "${TOOL_ROOT}/lib/python.sh"
    detect_python 2>/dev/null || true

    echo
    echo -e "${BOLD}Usage after install (no sudo needed):${NC}"
    echo "  iitd-proxy <role> <userid>    # enable proxy system-wide"
    echo "  iitd-proxy logout             # remove proxy from system"
    echo "  iitd-proxy shell              # interactive login"
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
    echo "Admin installs once (menu → Proxy Setup). After that any user can login/logout."
    echo "Proxy applies to: apt, snap, git/GitHub, GNOME GUI, wget, curl, Chrome, Chromium, Firefox"
    echo "HTTPS login uses system CAs first; TLS verify-off fallback if needed (no custom cert)."
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
    echo "After install, any user enables proxy with (no sudo):"
    echo "  iitd-proxy <role> <userid>"
    echo
    echo "Passwordless sudoers rule will be installed at ${SUDOERS_DEST}"
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
