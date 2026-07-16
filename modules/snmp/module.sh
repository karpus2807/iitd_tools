#!/usr/bin/env bash
# SNMP Setup module

MODULE_ID="snmp"
MODULE_NAME="SNMP Setup"
MODULE_DESCRIPTION="Install/configure/remove snmpd (v2c lab monitoring)"
MODULE_ORDER=50

module_supported_versions() {
    echo "all"
}

module_run() {
    run_snmp_menu || true
}
