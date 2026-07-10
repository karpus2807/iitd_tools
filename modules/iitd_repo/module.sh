#!/usr/bin/env bash
# IITD Repository Setup Module — submenu for individual repo actions

MODULE_ID="iitd_repo"
MODULE_NAME="IITD Repository Setup"
MODULE_DESCRIPTION="Configure IITD apt mirror, disable extra repos, restore backups"
MODULE_ORDER=10

module_supported_versions() {
    echo "all"
}

show_repo_submenu() {
    local official_src
    official_src="$(official_sources_filename)"

    clear
    echo -e "${BOLD}${CYAN}IITD Repository Setup${NC}"
    echo
    print_system_info
    print_iitd_paths_info
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Backup sources.list"
    echo "  2) Apply IITD mirror (sources.list)"
    echo "  3) Disable ${official_src}"
    echo "  4) Disable 3rd party repositories"
    echo "  5) Run apt update"
    echo "  6) Restore original repository status"
    echo
    echo "  b) Back to main menu"
    echo
}

module_run() {
    local ubuntu_version="$1"
    local ubuntu_codename="$2"
    local choice

    while true; do
        show_repo_submenu
        read -r -p "Select option [1-6, b]: " choice

        case "${choice}" in
            1)
                echo
                repo_action_backup_sources || true
                pause
                ;;
            2)
                echo
                if confirm "Apply IITD mirror for ${ubuntu_version} (${ubuntu_codename})?"; then
                    repo_action_apply_iitd_mirror "${ubuntu_version}" "${ubuntu_codename}" || true
                else
                    log_info "Cancelled."
                fi
                pause
                ;;
            3)
                echo
                if confirm "Disable ${SOURCES_LIST_D}/$(official_sources_filename)?"; then
                    repo_action_disable_ubuntu_sources || true
                else
                    log_info "Cancelled."
                fi
                pause
                ;;
            4)
                echo
                if confirm "Disable all 3rd party repos in sources.list.d?"; then
                    repo_action_disable_third_party || true
                else
                    log_info "Cancelled."
                fi
                pause
                ;;
            5)
                echo
                repo_action_apt_update || true
                pause
                ;;
            6)
                echo
                repo_action_restore_all || true
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
