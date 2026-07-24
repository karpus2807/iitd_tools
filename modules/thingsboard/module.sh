#!/usr/bin/env bash
# ThingsBoard MQTT telemetry module (Raspberry Pi 3 / 4)

MODULE_ID="thingsboard"
MODULE_NAME="ThingsBoard Telemetry"
MODULE_DESCRIPTION="Send Pi/lab telemetry to ThingsBoard MQTT (Pi 3/4)"
MODULE_ORDER=55

module_supported_versions() {
    echo "all"
}

module_run() {
    run_thingsboard_menu || true
}
