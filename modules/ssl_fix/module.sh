#!/usr/bin/env bash
# SSL Fix module — repair CA trust / certificate verify failures

MODULE_ID="ssl_fix"
MODULE_NAME="SSL Fix"
MODULE_DESCRIPTION="Remove broken custom CAs, reinstall ca-certificates, refresh trust store"
MODULE_ORDER=40

module_supported_versions() {
    echo "all"
}

module_run() {
    echo
    run_ssl_fix || true
}
