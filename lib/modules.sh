#!/usr/bin/env bash
# Module discovery and menu management

declare -a MODULE_IDS=()
declare -A MODULE_NAMES=()
declare -A MODULE_DESCRIPTIONS=()
declare -A MODULE_ORDERS=()
declare -A MODULE_PATHS=()

discover_modules() {
    local modules_dir="${TOOL_ROOT}/modules"

    if [[ ! -d "${modules_dir}" ]]; then
        log_warn "No modules directory found at ${modules_dir}"
        return 0
    fi

    local module_file
    while IFS= read -r -d '' module_file; do
        # shellcheck source=/dev/null
        source "${module_file}"

        if [[ -z "${MODULE_ID:-}" ]]; then
            log_warn "Skipping ${module_file}: MODULE_ID not defined"
            continue
        fi

        if ! declare -f module_run &>/dev/null; then
            log_warn "Skipping ${module_file}: module_run() not defined"
            continue
        fi

        MODULE_IDS+=("${MODULE_ID}")
        MODULE_NAMES["${MODULE_ID}"]="${MODULE_NAME:-${MODULE_ID}}"
        MODULE_DESCRIPTIONS["${MODULE_ID}"]="${MODULE_DESCRIPTION:-}"
        MODULE_ORDERS["${MODULE_ID}"]="${MODULE_ORDER:-100}"
        MODULE_PATHS["${MODULE_ID}"]="${module_file}"

        unset MODULE_ID MODULE_NAME MODULE_DESCRIPTION MODULE_ORDER
    done < <(find "${modules_dir}" -mindepth 2 -maxdepth 2 -name 'module.sh' -print0 | sort -z)

    # Sort by MODULE_ORDER, then name
    if [[ ${#MODULE_IDS[@]} -gt 0 ]]; then
        local sorted
        sorted="$(
            for id in "${MODULE_IDS[@]}"; do
                printf '%s\t%s\n' "${MODULE_ORDERS[${id}]}" "${id}"
            done | sort -n -k1,1 -k2,2 | cut -f2
        )"
        readarray -t MODULE_IDS <<< "${sorted}"
    fi
}

module_is_supported() {
    local module_id="$1"

    if ! declare -f module_supported_versions &>/dev/null; then
        return 0
    fi

    # shellcheck source=/dev/null
    source "${MODULE_PATHS[${module_id}]}"

    local supported
    supported="$(module_supported_versions)"

    if [[ "${supported}" == "all" || -z "${supported}" ]]; then
        return 0
    fi

    for ver in ${supported}; do
        if [[ "${ver}" == "${UBUNTU_VERSION}" ]]; then
            return 0
        fi
    done

    return 1
}

show_main_menu() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     IITD Lab Setup Tool                  ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo
    print_system_info
    print_python_info
    print_deps_info
    echo

    if [[ ${#MODULE_IDS[@]} -eq 0 ]]; then
        log_warn "No modules found. Add modules under: ${TOOL_ROOT}/modules/"
        echo
        echo "  q) Quit"
        echo
        return 0
    fi

    echo -e "${BOLD}Available modules:${NC}"
    echo

    local i=1
    local id
    for id in "${MODULE_IDS[@]}"; do
        local desc="${MODULE_DESCRIPTIONS[${id}]}"
        local supported_marker=""

        if ! module_is_supported "${id}"; then
            supported_marker=" ${YELLOW}(not supported on ${UBUNTU_VERSION})${NC}"
        fi

        echo -e "  ${BOLD}${i})${NC} ${MODULE_NAMES[${id}]}${supported_marker}"
        if [[ -n "${desc}" ]]; then
            echo -e "     ${desc}"
        fi
        ((i++)) || true
    done

    echo
    echo "  q) Quit"
    echo
}

run_main_menu() {
    while true; do
        show_main_menu

        if [[ ${#MODULE_IDS[@]} -eq 0 ]]; then
            read -r -p "Choice: " choice
            [[ "${choice}" == "q" || "${choice}" == "Q" ]] && break
            log_warn "Invalid choice"
            pause
            continue
        fi

        read -r -p "Select module [1-${#MODULE_IDS[@]}, q]: " choice

        if [[ "${choice}" == "q" || "${choice}" == "Q" ]]; then
            echo "Goodbye!"
            break
        fi

        if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#MODULE_IDS[@]} )); then
            log_warn "Invalid choice: ${choice}"
            pause
            continue
        fi

        local module_id="${MODULE_IDS[$((choice - 1))]}"

        if ! module_is_supported "${module_id}"; then
            log_error "Module '${MODULE_NAMES[${module_id}]}' does not support ${OS_ID:-ubuntu} ${UBUNTU_VERSION}"
            pause
            continue
        fi

        echo
        log_info "Running: ${MODULE_NAMES[${module_id}]}"
        echo

        # shellcheck source=/dev/null
        source "${MODULE_PATHS[${module_id}]}"
        module_run "${UBUNTU_VERSION}" "${UBUNTU_CODENAME}" || {
            log_error "Module failed: ${MODULE_NAMES[${module_id}]}"
        }

        echo
        pause
    done
}
