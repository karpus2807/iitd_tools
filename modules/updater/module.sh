#!/usr/bin/env bash
# Tool updater module — GitHub latest 5 updates (upgrade / downgrade)

MODULE_ID="updater"
MODULE_NAME="Tool Updater"
MODULE_DESCRIPTION="Install latest GitHub updates or downgrade (keeps backups)"
MODULE_ORDER=6

module_supported_versions() {
    echo "all"
}

module_run() {
    run_updater_menu || true
}
