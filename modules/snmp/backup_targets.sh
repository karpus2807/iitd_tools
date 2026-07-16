#!/usr/bin/env bash
# SNMP-related backup targets (auto-loaded by Backups menu)

backups_register "snmpd.conf" \
    "SNMP daemon config (snmpd.conf)" \
    "/etc/snmp/snmpd.conf" \
    "snmpd.conf"
