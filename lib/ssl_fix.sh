#!/usr/bin/env bash
# SSL / CA trust repair + IITD ca-chain install for lab systems (Ubuntu 16–26 / Debian 10–13)

IITD_CA_CHAIN_SRC="${TOOL_ROOT}/config/certs/ca-chain.crt"
IITD_CA_CHAIN_TOOL_DIR="/usr/local/lib/iitd-tool/certs"
IITD_CA_CHAIN_TOOL_DST="${IITD_CA_CHAIN_TOOL_DIR}/ca-chain.crt"
IITD_CA_SHARE_DIR="/usr/local/share/ca-certificates"
IITD_CA_CHAIN_PREFIX="iitd-ca-chain"

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

    # Leftover CCIITD names only — never touch iitd-ca-chain*
    local found
    while IFS= read -r found; do
        [[ -z "${found}" ]] && continue
        rm -f "${found}"
        log_info "Removed: ${found}"
        removed=1
    done < <(
        find /usr/local/share/ca-certificates /usr/share/ca-certificates /etc/ssl/certs \
            \( -iname '*cciitd*' -o -iname 'iitd-cciitd*' \) \
            ! -iname "${IITD_CA_CHAIN_PREFIX}*" \
            2>/dev/null || true
    )

    if [[ -d "${IITD_CA_CHAIN_TOOL_DIR}" ]] && [[ ! -e "${IITD_CA_CHAIN_TOOL_DST}" ]]; then
        rmdir "${IITD_CA_CHAIN_TOOL_DIR}" 2>/dev/null || true
    fi

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

ssl_ca_chain_source_path() {
    if [[ -f "${IITD_CA_CHAIN_SRC}" ]]; then
        printf '%s\n' "${IITD_CA_CHAIN_SRC}"
        return 0
    fi
    return 1
}

# Split a PEM bundle into numbered .crt files in dest_dir
ssl_ca_chain_split_to_dir() {
    local src="$1"
    local dest_dir="$2"
    local count

    mkdir -p "${dest_dir}"
    rm -f "${dest_dir}/${IITD_CA_CHAIN_PREFIX}"-*.crt 2>/dev/null || true

    count="$(
        awk -v dest="${dest_dir}" -v prefix="${IITD_CA_CHAIN_PREFIX}" '
            /-----BEGIN CERTIFICATE-----/ {
                n++
                fn = sprintf("%s/%s-%02d.crt", dest, prefix, n)
                printing = 1
            }
            printing { print > fn }
            /-----END CERTIFICATE-----/ {
                printing = 0
                close(fn)
            }
            END { print n+0 }
        ' "${src}"
    )"

    [[ "${count}" -gt 0 ]]
}

ssl_ca_chain_validate() {
    local src="$1"
    local tmpdir pem count=0

    if [[ ! -f "${src}" ]]; then
        log_error "Certificate file not found: ${src}"
        return 1
    fi

    if ! grep -q "BEGIN CERTIFICATE" "${src}"; then
        log_error "Not a PEM certificate bundle: ${src}"
        return 1
    fi

    tmpdir="$(mktemp -d)"
    if ! ssl_ca_chain_split_to_dir "${src}" "${tmpdir}"; then
        rm -rf "${tmpdir}"
        log_error "Failed to parse certificate bundle: ${src}"
        return 1
    fi

    if command -v openssl >/dev/null 2>&1; then
        for pem in "${tmpdir}/${IITD_CA_CHAIN_PREFIX}"-*.crt; do
            [[ -f "${pem}" ]] || continue
            if ! openssl x509 -in "${pem}" -noout >/dev/null 2>&1; then
                rm -rf "${tmpdir}"
                log_error "Invalid certificate in bundle: ${pem}"
                return 1
            fi
            count=$((count + 1))
        done
    else
        shopt -s nullglob
        local files=( "${tmpdir}/${IITD_CA_CHAIN_PREFIX}"-*.crt )
        shopt -u nullglob
        count="${#files[@]}"
        log_warn "openssl not found — skipped deep validation"
    fi

    rm -rf "${tmpdir}"

    if [[ "${count}" -eq 0 ]]; then
        log_error "No certificates found in: ${src}"
        return 1
    fi

    log_info "Validated PEM bundle: ${count} certificate(s)"
    return 0
}

ssl_ca_chain_remove_installed_share_files() {
    local f
    shopt -s nullglob
    for f in "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}"-*.crt \
             "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}.crt"; do
        [[ -e "${f}" ]] || continue
        rm -f "${f}"
        log_info "Removed previous: ${f}"
    done
    shopt -u nullglob
}

ssl_ca_chain_is_installed() {
    local files
    shopt -s nullglob
    files=( "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}"-*.crt )
    shopt -u nullglob
    [[ ${#files[@]} -gt 0 && -f "${IITD_CA_CHAIN_TOOL_DST}" ]]
}

ssl_ca_chain_ensure_ca_certificates_pkg() {
    if command -v update-ca-certificates >/dev/null 2>&1; then
        return 0
    fi

    log_info "Installing ca-certificates package..."
    apt-get update -qq || true
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates; then
        log_error "Failed to install ca-certificates"
        return 1
    fi
}

# Apply bundled ca-chain into system trust store (no prompts).
# Returns count of installed leaf files via echo to fd3 when used carefully — just log + status code.
ssl_ca_chain_apply() {
    local src="$1"
    local quiet="${2:-0}"
    local tmpdir count=0 pem dest

    if ! ssl_ca_chain_validate "${src}"; then
        return 1
    fi

    if ! ssl_ca_chain_ensure_ca_certificates_pkg; then
        return 1
    fi

    tmpdir="$(mktemp -d)"
    if ! ssl_ca_chain_split_to_dir "${src}" "${tmpdir}"; then
        rm -rf "${tmpdir}"
        log_error "Failed to split certificate bundle"
        return 1
    fi

    [[ "${quiet}" == "1" ]] || log_info "Removing previous IITD ca-chain trust files (if any)..."
    ssl_ca_chain_remove_installed_share_files

    mkdir -p "${IITD_CA_SHARE_DIR}" "${IITD_CA_CHAIN_TOOL_DIR}"

    for pem in "${tmpdir}/${IITD_CA_CHAIN_PREFIX}"-*.crt; do
        [[ -f "${pem}" ]] || continue
        dest="${IITD_CA_SHARE_DIR}/$(basename "${pem}")"
        install -m 0644 "${pem}" "${dest}"
        log_success "Installed: ${dest}"
        if command -v openssl >/dev/null 2>&1; then
            openssl x509 -in "${dest}" -noout -subject 2>/dev/null | sed 's/^/    /' || true
        fi
        count=$((count + 1))
    done

    rm -rf "${tmpdir}"

    if [[ "${count}" -eq 0 ]]; then
        log_error "No certificates were installed"
        return 1
    fi

    install -m 0644 "${src}" "${IITD_CA_CHAIN_TOOL_DST}"
    log_success "Saved tool copy: ${IITD_CA_CHAIN_TOOL_DST}"

    log_info "Updating system CA trust store..."
    if update-ca-certificates; then
        log_success "System trust store updated (${count} cert(s) from ca-chain)"
        return 0
    fi

    log_error "update-ca-certificates failed"
    return 1
}

ssl_ca_chain_show_status() {
    local src
    echo
    echo -e "${BOLD}IITD CA chain status${NC}"
    echo

    if src="$(ssl_ca_chain_source_path)"; then
        echo -e "${BOLD}Bundled source:${NC} ${src}"
        if command -v openssl >/dev/null 2>&1; then
            openssl crl2pkcs7 -nocrl -certfile "${src}" 2>/dev/null \
                | openssl pkcs7 -print_certs -noout 2>/dev/null \
                | sed 's/^/  /' || true
        fi
    else
        echo -e "${BOLD}Bundled source:${NC} ${YELLOW}missing${NC} (${IITD_CA_CHAIN_SRC})"
    fi

    echo
    if [[ -f "${IITD_CA_CHAIN_TOOL_DST}" ]]; then
        echo -e "${BOLD}Tool copy:${NC} ${GREEN}${IITD_CA_CHAIN_TOOL_DST}${NC}"
    else
        echo -e "${BOLD}Tool copy:${NC} ${YELLOW}not installed${NC}"
    fi

    echo -e "${BOLD}System trust files:${NC}"
    local found=0
    local f
    shopt -s nullglob
    for f in "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}"-*.crt \
             "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}.crt"; do
        echo "  ${GREEN}${f}${NC}"
        if command -v openssl >/dev/null 2>&1; then
            openssl x509 -in "${f}" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/    /' || true
        fi
        found=1
    done
    shopt -u nullglob

    if [[ "${found}" -eq 0 ]]; then
        echo -e "  ${YELLOW}not installed${NC}"
    fi
    echo
}

# mode: install | update
ssl_ca_chain_install() {
    local mode="${1:-install}"
    local src

    require_root

    if ! src="$(ssl_ca_chain_source_path)"; then
        log_error "Bundled certificate missing: ${IITD_CA_CHAIN_SRC}"
        return 1
    fi

    echo
    if [[ "${mode}" == "update" ]]; then
        echo -e "${BOLD}${CYAN}Update Certificate — IITD ca-chain${NC}"
    else
        echo -e "${BOLD}${CYAN}Install Certificate — IITD ca-chain${NC}"
    fi
    echo
    echo "Source: ${src}"
    echo "Installs into system trust store:"
    echo "  ${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}-NN.crt"
    echo "Also keeps a copy at:"
    echo "  ${IITD_CA_CHAIN_TOOL_DST}"
    echo

    if [[ "${mode}" == "update" ]]; then
        if ! ssl_ca_chain_is_installed; then
            log_warn "Certificate not installed yet — running install instead of update."
        fi
        if ! confirm "Update IITD ca-chain certificate now?"; then
            log_info "Cancelled."
            return 0
        fi
    else
        if ssl_ca_chain_is_installed; then
            log_info "Certificate already installed — will overwrite / refresh trust store."
        fi
        if ! confirm "Install IITD ca-chain certificate now?"; then
            log_info "Cancelled."
            return 0
        fi
    fi

    echo
    if ! ssl_ca_chain_apply "${src}"; then
        return 1
    fi

    ssl_ca_chain_show_status
    log_success "Certificate ${mode} finished."
    return 0
}

run_ssl_install_certificate() {
    ssl_ca_chain_install install
}

run_ssl_update_certificate() {
    ssl_ca_chain_install update
}

# Remove IITD ca-chain + all local custom CAs; resync trust store to distro official certs.
ssl_remove_local_custom_certificates() {
    local removed=0
    local f
    local before=0

    shopt -s nullglob
    local existing=(
        "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}"-*.crt
        "${IITD_CA_SHARE_DIR}/${IITD_CA_CHAIN_PREFIX}.crt"
    )
    shopt -u nullglob
    before="${#existing[@]}"

    # IITD ca-chain trust files
    ssl_ca_chain_remove_installed_share_files
    if [[ "${before}" -gt 0 ]]; then
        removed=1
    fi

    if [[ -e "${IITD_CA_CHAIN_TOOL_DST}" ]]; then
        rm -f "${IITD_CA_CHAIN_TOOL_DST}"
        log_info "Removed: ${IITD_CA_CHAIN_TOOL_DST}"
        removed=1
    fi

    # Any other admin-added certs under /usr/local/share/ca-certificates
    # (official Ubuntu/Debian CAs live under /usr/share/ca-certificates — not touched here)
    if [[ -d "${IITD_CA_SHARE_DIR}" ]]; then
        while IFS= read -r -d '' f; do
            rm -f "${f}"
            log_info "Removed local custom CA: ${f}"
            removed=1
        done < <(find "${IITD_CA_SHARE_DIR}" -type f \( -iname '*.crt' -o -iname '*.pem' \) -print0 2>/dev/null || true)

        # Clean empty dirs left behind
        find "${IITD_CA_SHARE_DIR}" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    fi

    # Legacy CCIITD / old tool copies
    ssl_fix_remove_legacy_ca

    # Drop remaining files in tool certs dir, then remove dir if empty
    if [[ -d "${IITD_CA_CHAIN_TOOL_DIR}" ]]; then
        while IFS= read -r -d '' f; do
            rm -f "${f}"
            log_info "Removed: ${f}"
            removed=1
        done < <(find "${IITD_CA_CHAIN_TOOL_DIR}" -type f -print0 2>/dev/null || true)
        rmdir "${IITD_CA_CHAIN_TOOL_DIR}" 2>/dev/null || true
    fi

    if [[ "${removed}" -eq 0 ]]; then
        log_info "No local custom certificate files found under ${IITD_CA_SHARE_DIR}."
    fi
}

run_ssl_remove_certificate() {
    require_root

    echo
    echo -e "${BOLD}${CYAN}Remove Certificate — sync to official Ubuntu/Debian CAs${NC}"
    echo
    echo "This will:"
    echo "  1. Remove IITD ca-chain installed by this tool"
    echo "  2. Remove other local/custom CAs from:"
    echo "       ${IITD_CA_SHARE_DIR}"
    echo "  3. Remove legacy CCIITD / tool cert copies"
    echo "  4. Reinstall package: ca-certificates (official store)"
    echo "  5. Rebuild trust store: update-ca-certificates --fresh"
    echo
    echo "Official package CAs under /usr/share/ca-certificates stay (restored by reinstall)."
    echo

    if ! confirm "Remove IITD ca-chain now?"; then
        log_info "Cancelled."
        return 0
    fi

    local purge_all=0
    if confirm "Also remove ALL other local custom CAs under ${IITD_CA_SHARE_DIR} and sync to official store?"; then
        purge_all=1
    fi

    echo
    log_info "Step 1/3: Remove certificates..."
    if [[ "${purge_all}" -eq 1 ]]; then
        ssl_remove_local_custom_certificates
    else
        ssl_ca_chain_remove_installed_share_files
        if [[ -e "${IITD_CA_CHAIN_TOOL_DST}" ]]; then
            rm -f "${IITD_CA_CHAIN_TOOL_DST}"
            log_info "Removed: ${IITD_CA_CHAIN_TOOL_DST}"
        fi
        ssl_fix_remove_legacy_ca
        if [[ -d "${IITD_CA_CHAIN_TOOL_DIR}" ]] && [[ ! -e "${IITD_CA_CHAIN_TOOL_DST}" ]]; then
            rmdir "${IITD_CA_CHAIN_TOOL_DIR}" 2>/dev/null || true
        fi
    fi

    echo
    log_info "Step 2/3: Reinstall official ca-certificates..."
    ssl_fix_reinstall_ca_packages || true

    echo
    log_info "Step 3/3: Rebuild trust store from official certs..."
    ssl_fix_refresh_trust_store || true

    ssl_ca_chain_show_status
    ssl_fix_show_time_hint
    ssl_fix_test_https || true

    echo
    log_success "Remove Certificate finished."
    echo
}

run_ssl_fix() {
    local src

    require_root

    echo
    echo -e "${BOLD}${CYAN}SSL Fix — repair system CA trust${NC}"
    echo
    echo "This will:"
    echo "  1. Remove leftover custom IITD / CCIITD CA certificate files"
    echo "  2. Reinstall package: ca-certificates"
    echo "  3. Refresh system trust store (update-ca-certificates --fresh)"
    echo "  4. Re-apply IITD ca-chain (if bundled) so it stays trusted"
    echo "  5. Show system time + optional HTTPS test"
    echo
    echo "Does NOT change IITD apt mirror or disable proxy permanently."
    echo

    if ! confirm "Run SSL Fix now?"; then
        log_info "Cancelled."
        return 0
    fi

    echo
    log_info "Step 1/4: Remove legacy custom CA files..."
    ssl_fix_remove_legacy_ca

    echo
    log_info "Step 2/4: Reinstall CA packages..."
    ssl_fix_reinstall_ca_packages || true

    echo
    log_info "Step 3/4: Refresh trust store..."
    ssl_fix_refresh_trust_store || true

    echo
    log_info "Step 4/4: Ensure IITD ca-chain is installed..."
    if src="$(ssl_ca_chain_source_path)"; then
        ssl_ca_chain_apply "${src}" 1 || log_warn "IITD ca-chain re-apply failed"
    else
        log_warn "Bundled ca-chain not found — skipped re-apply"
    fi

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

show_ssl_submenu() {
    clear
    echo -e "${BOLD}${CYAN}SSL / Certificates${NC}"
    echo
    print_system_info

    if ssl_ca_chain_is_installed; then
        echo -e "${BOLD}IITD ca-chain:${NC} ${GREEN}installed${NC}"
        echo -e "  ${IITD_CA_CHAIN_TOOL_DST}"
    else
        echo -e "${BOLD}IITD ca-chain:${NC} ${YELLOW}not installed${NC}"
    fi
    if [[ -f "${IITD_CA_CHAIN_SRC}" ]]; then
        echo -e "${BOLD}Bundled cert:${NC} config/certs/ca-chain.crt"
    else
        echo -e "${BOLD}Bundled cert:${NC} ${YELLOW}missing${NC}"
    fi
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Install Certificate (ca-chain)"
    echo "  2) Update Certificate (refresh ca-chain)"
    echo "  3) Remove Certificate (sync to official CAs)"
    echo "  4) Certificate Status"
    echo "  5) SSL Fix (repair trust store)"
    echo
    echo "  b) Back to main menu"
    echo
}

run_ssl_menu() {
    local choice

    while true; do
        show_ssl_submenu
        read -r -p "Select option [1-5, b]: " choice

        case "${choice}" in
            1)
                run_ssl_install_certificate || true
                pause
                ;;
            2)
                run_ssl_update_certificate || true
                pause
                ;;
            3)
                run_ssl_remove_certificate || true
                pause
                ;;
            4)
                ssl_ca_chain_show_status || true
                pause
                ;;
            5)
                run_ssl_fix || true
                pause
                ;;
            b|B)
                return 0
                ;;
            *)
                log_warn "Invalid option: ${choice}"
                sleep 1
                ;;
        esac
    done
}
