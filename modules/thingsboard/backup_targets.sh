#!/usr/bin/env bash
# ThingsBoard config backup target

backups_register "iitd-thingsboard.conf" \
    "ThingsBoard telemetry config" \
    "/etc/iitd-thingsboard.conf" \
    "iitd-thingsboard.conf"
