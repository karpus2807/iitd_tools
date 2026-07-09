#!/usr/bin/env bash
# IITD Tool system install / uninstall module

MODULE_ID="system"
MODULE_NAME="IITD Tool Management"
MODULE_DESCRIPTION="Install or uninstall tool system-wide (/etc/iitd-tool)"
MODULE_ORDER=5

module_supported_versions() {
    echo "all"
}

show_system_submenu() {
    clear
    echo -e "${BOLD}${CYAN}IITD Tool Management${NC}"
    echo
    show_tool_install_status
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Install tool system-wide"
    echo "  2) Uninstall tool"
    echo "  3) Show install status"
    echo
    echo "  b) Back to main menu"
    echo
}

module_run() {
    local choice

    while true; do
        show_system_submenu
        read -r -p "Select option [1-3, b]: " choice

        case "${choice}" in
            1)
                echo
                install_iitd_tool_system || true
                pause
                ;;
            2)
                echo
                uninstall_iitd_tool_system || true
                pause
                ;;
            3)
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
