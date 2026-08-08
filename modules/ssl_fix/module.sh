#!/usr/bin/env bash
# SSL / Certificates module — install ca-chain + repair CA trust

MODULE_ID="ssl_fix"
MODULE_NAME="SSL / Certificates"
MODULE_DESCRIPTION="Install/update IITD ca-chain, repair CA trust / certificate verify failures"
MODULE_ORDER=40

module_supported_versions() {
    echo "all"
}

module_run() {
    run_ssl_menu || true
}
