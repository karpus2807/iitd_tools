#!/usr/bin/env bash
# Basic tools installer module — checkbox list, apt install selected

MODULE_ID="basic_tools"
MODULE_NAME="Basic Tools Installer"
MODULE_DESCRIPTION="Install common CLI tools (wget, curl, tmux, ssh, ...)"
MODULE_ORDER=30

module_supported_versions() {
    echo "all"
}

module_run() {
    echo
    log_info "Opening basic tools checklist..."
    echo
    run_basic_tools_installer || true
}
