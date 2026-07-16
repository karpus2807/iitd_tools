#!/usr/bin/env bash
# SSL / CA trust repair for lab systems (Ubuntu 16–26 / Debian 10–13)

ssl_fix_remove_legacy_ca() {
    local removed=0
    local f

    for f in \
        "/usr/local/share/ca-certificates/iitd-cciitd-ca.crt" \
        "/usr/local/lib/iitd-tool/certs/CCIITD-CA.crt" \
        "/etc/ssl/certs/iitd-cciitd-ca.pem"; do
        if [[ -e "${f}" ]]; then
            rm -f "${f}"
            log_info "Removed: ${f}"
            removed=1
        fi
    done

    # Any leftover custom IITD / CCIITD names under CA dirs
    local found
    while IFS= read -r found; do
        [[ -z "${found}" ]] && continue
        rm -f "${found}"
        log_info "Removed: ${found}"
        removed=1
    done < <(
        find /usr/local/share/ca-certificates /usr/share/ca-certificates /etc/ssl/certs \
            \( -iname '*iitd*cciitd*' -o -iname '*cciitd*' -o -iname 'iitd-cciitd*' \) \
            2>/dev/null || true
    )

    rmdir /usr/local/lib/iitd-tool/certs 2>/dev/null || true

    if [[ "${removed}" -eq 0 ]]; then
        log_info "No legacy IITD CA certificate files found."
    fi
}

ssl_fix_refresh_trust_store() {
    if ! command -v update-ca-certificates >/dev/null 2>&1; then
        log_warn "update-ca-certificates not found"
        return 1
    fi

    log_info "Refreshing system CA trust store (--fresh)..."
    if update-ca-certificates --fresh; then
        log_success "CA trust store refreshed"
        return 0
    fi

    log_warn "update-ca-certificates --fresh failed; trying without --fresh"
    update-ca-certificates || true
}

ssl_fix_reinstall_ca_packages() {
    log_info "Reinstalling ca-certificates (and openssl if available)..."

    if ! apt-get update -qq; then
        log_warn "apt-get update failed (proxy/network?). Continuing with reinstall anyway..."
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y ca-certificates; then
        log_success "Reinstalled: ca-certificates"
    else
        log_error "Failed to reinstall ca-certificates"
        return 1
    fi

    if package_installed openssl 2>/dev/null || dpkg-query -W -f='${Status}' openssl 2>/dev/null | grep -q "install ok installed"; then
        DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y openssl || log_warn "openssl reinstall skipped"
    fi
}

ssl_fix_show_time_hint() {
    echo
    echo -e "${BOLD}System time:${NC} $(date -R 2>/dev/null || date)"
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl status 2>/dev/null | head -n 5 || true
    fi
    log_info "Wrong system date/time also causes certificate errors — fix NTP if date looks wrong."
}

ssl_fix_test_https() {
    echo
    log_info "Testing HTTPS (may need IITD proxy on campus)..."

    local url="https://archive.ubuntu.com/ubuntu/"
    if [[ "${OS_ID:-ubuntu}" == "debian" ]]; then
        url="https://deb.debian.org/debian/"
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSI --max-time 15 "${url}" >/dev/null 2>&1; then
            log_success "HTTPS OK: ${url}"
            return 0
        fi
        log_warn "HTTPS still failing for ${url}"
        log_info "If you are on campus, run: sudo iitd-proxy <role> <userid>  then retry apt/upgrade."
        return 1
    fi

    log_info "curl not installed — skip HTTPS test"
    return 0
}

run_ssl_fix() {
    require_root

    echo
    echo -e "${BOLD}${CYAN}SSL Fix — repair system CA trust${NC}"
    echo
    echo "This will:"
    echo "  1. Remove leftover custom IITD / CCIITD CA certificate files"
    echo "  2. Reinstall package: ca-certificates"
    echo "  3. Refresh system trust store (update-ca-certificates --fresh)"
    echo "  4. Show system time + optional HTTPS test"
    echo
    echo "Does NOT change IITD apt mirror or disable proxy permanently."
    echo

    if ! confirm "Run SSL Fix now?"; then
        log_info "Cancelled."
        return 0
    fi

    echo
    log_info "Step 1/3: Remove legacy custom CA files..."
    ssl_fix_remove_legacy_ca

    echo
    log_info "Step 2/3: Reinstall CA packages..."
    ssl_fix_reinstall_ca_packages || true

    echo
    log_info "Step 3/3: Refresh trust store..."
    ssl_fix_refresh_trust_store || true

    ssl_fix_show_time_hint
    ssl_fix_test_https || true

    echo
    log_success "SSL Fix finished."
    echo
    echo "Next (campus):"
    echo "  sudo iitd-proxy <role> <userid>   # proxy ON for updates"
    echo "  sudo apt-get update"
    echo "  sudo do-release-upgrade          # if upgrading"
    echo
}
