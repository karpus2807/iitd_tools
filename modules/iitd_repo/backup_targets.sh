#!/usr/bin/env bash
# Optional extension for Backups & Restore.
# This file is auto-sourced when the Backups menu opens.
#
# Example — register an extra file:
#   backups_register "apt_conf_proxy" \
#       "Legacy apt proxy.conf" \
#       "/etc/apt/apt.conf.d/proxy.conf" \
#       "apt-proxy.conf"
#
# Example — custom handlers:
#   my_backup()  { local id="$1"; ...; }
#   my_restore() { local id="$1"; local snap="${2:-}"; ...; }
#   backups_register "my_id" "My thing" "/path" "my_label"
#   backups_register_fn "my_id" my_backup my_restore
#
# Left empty by default (targets come from config/backup-targets.list).
