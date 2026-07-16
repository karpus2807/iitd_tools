#!/usr/bin/env bash
# Unified backups & restore module

MODULE_ID="backups"
MODULE_NAME="Backups & Restore"
MODULE_DESCRIPTION="Extensible backup/restore — all or particular files/configs"
MODULE_ORDER=8

module_supported_versions() {
    echo "all"
}

module_run() {
    run_backups_menu || true
}
