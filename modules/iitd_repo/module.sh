#!/usr/bin/env bash
# IITD Repository Setup Module
#
# Adds IITD mirror entries to /etc/apt/sources.list
# and disables official Ubuntu repos in sources.list.d/ubuntu.sources

MODULE_ID="iitd_repo"
MODULE_NAME="IITD Repository Setup"
MODULE_DESCRIPTION="Configure IITD apt mirror and disable official Ubuntu repos"
MODULE_ORDER=10

module_supported_versions() {
    echo "all"
}

module_run() {
    local ubuntu_version="$1"
    local ubuntu_codename="$2"

    echo "This will:"
    echo "  1. Backup and replace /etc/apt/sources.list with IITD mirror config"
    echo "  2. Disable /etc/apt/sources.list.d/ubuntu.sources (if present)"
    echo "  3. Run apt update"
    echo
    echo "Ubuntu: ${ubuntu_version} (${ubuntu_codename})"
    echo

    if ! confirm "Proceed with IITD repository setup?"; then
        log_info "Cancelled."
        return 0
    fi

    require_root

    local sources_list="/etc/apt/sources.list"
    local ubuntu_sources="/etc/apt/sources.list.d/ubuntu.sources"
    local temp_sources
    temp_sources="$(mktemp)"

    if ! generate_sources_list "${ubuntu_version}" "${ubuntu_codename}" "${temp_sources}"; then
        rm -f "${temp_sources}"
        return 1
    fi

    # Step 1: Configure sources.list
    backup_file "${sources_list}"
    cp "${temp_sources}" "${sources_list}"
    rm -f "${temp_sources}"
    chmod 644 "${sources_list}"
    log_success "Installed IITD sources -> ${sources_list}"

    # Step 2: Disable official ubuntu.sources (24.04+)
    if [[ -f "${ubuntu_sources}" ]]; then
        backup_file "${ubuntu_sources}"
        mv "${ubuntu_sources}" "${ubuntu_sources}.disabled"
        log_success "Disabled official repos: ${ubuntu_sources} -> ${ubuntu_sources}.disabled"
    else
        log_info "No ubuntu.sources found (may already be disabled)"
    fi

    # Step 3: apt update
    echo
    log_info "Running apt update..."
    if apt update; then
        log_success "apt update completed successfully"
    else
        log_warn "apt update finished with errors — check network/proxy settings"
        return 1
    fi

    log_success "IITD repository setup complete!"
}
