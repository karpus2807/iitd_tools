#!/usr/bin/env bash
# Basic tools checklist and installation

BASIC_TOOLS_LIST="${TOOL_ROOT}/config/basic-tools.list"

declare -a TOOL_PACKAGES=()
declare -a TOOL_LABELS=()

load_basic_tools_list() {
    TOOL_PACKAGES=()
    TOOL_LABELS=()

    if [[ ! -f "${BASIC_TOOLS_LIST}" ]]; then
        log_error "Tools list not found: ${BASIC_TOOLS_LIST}"
        return 1
    fi

    local line pkg label
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "${line}" ]] && continue

        if [[ "${line}" == *"|"* ]]; then
            pkg="${line%%|*}"
            label="${line#*|}"
        else
            pkg="${line}"
            label="${line}"
        fi

        TOOL_PACKAGES+=("${pkg}")
        TOOL_LABELS+=("${label}")
    done < "${BASIC_TOOLS_LIST}"
}

tool_package_installed() {
    package_installed "$1"
}

tool_status_suffix() {
    local pkg="$1"
    if tool_package_installed "${pkg}"; then
        echo " [installed]"
    else
        echo ""
    fi
}

install_basic_tool_packages() {
    local -a selected=("$@")
    local pkg missing=()

    if [[ ${#selected[@]} -eq 0 ]]; then
        log_warn "No tools selected."
        return 0
    fi

    require_root

    for pkg in "${selected[@]}"; do
        if ! tool_package_installed "${pkg}"; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "All selected tools are already installed."
        return 0
    fi

    log_info "Installing: ${missing[*]}"

    if ! apt-get update -qq; then
        log_error "apt-get update failed"
        return 1
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
        log_success "Installation complete."
        return 0
    fi

    log_error "Installation failed."
    return 1
}

# Interactive checkbox UI (no whiptail required)
# Keys: up/down move, space toggle, enter confirm, q cancel
run_tools_checkbox_menu() {
    local count="${#TOOL_PACKAGES[@]}"
    local -a selected
    local current=0
    local i key

    if [[ "${count}" -eq 0 ]]; then
        log_error "No tools in list."
        return 1
    fi

    for ((i = 0; i < count; i++)); do
        selected[i]=0
    done

    while true; do
        clear
        echo -e "${BOLD}${CYAN}Basic Tools Installer${NC}"
        echo
        echo "  ↑/↓ or j/k move   SPACE toggle   ENTER install   q cancel"
        echo
        for ((i = 0; i < count; i++)); do
            local mark=" "
            local prefix="  "
            [[ "${selected[i]}" -eq 1 ]] && mark="x"
            [[ "${i}" -eq "${current}" ]] && prefix="> "
            local suffix
            suffix="$(tool_status_suffix "${TOOL_PACKAGES[i]}")"
            echo -e "${prefix}[${mark}] ${TOOL_LABELS[i]}${suffix}"
        done
        echo

        IFS= read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then
            read -rsn2 key
            case "${key}" in
                '[A') ((current > 0)) && ((current--)) ;;
                '[B') ((current < count - 1)) && ((current++)) ;;
            esac
        elif [[ "${key}" == " " ]]; then
            selected[current]=$((1 - selected[current]))
        elif [[ "${key}" == "" ]]; then
            break
        elif [[ "${key}" == "j" || "${key}" == "J" ]]; then
            ((current < count - 1)) && ((current++))
        elif [[ "${key}" == "k" || "${key}" == "K" ]]; then
            ((current > 0)) && ((current--))
        elif [[ "${key}" == "q" || "${key}" == "Q" ]]; then
            log_info "Cancelled."
            return 0
        fi
    done

    local -a to_install=()
    for ((i = 0; i < count; i++)); do
        if [[ "${selected[i]}" -eq 1 ]]; then
            to_install+=("${TOOL_PACKAGES[i]}")
        fi
    done

    echo
    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_warn "Nothing selected."
        return 0
    fi

    echo "Selected for install:"
    for pkg in "${to_install[@]}"; do
        echo "  - ${pkg}"
    done
    echo

    if confirm "Install selected tools?"; then
        install_basic_tool_packages "${to_install[@]}"
    else
        log_info "Cancelled."
    fi
}

# Fallback using whiptail when available
run_tools_whiptail_menu() {
    local args=() i pkg label suffix state
    local height width list_height

    for ((i = 0; i < ${#TOOL_PACKAGES[@]}; i++)); do
        pkg="${TOOL_PACKAGES[i]}"
        label="${TOOL_LABELS[i]}"
        suffix="$(tool_status_suffix "${pkg}")"
        state="OFF"
        tool_package_installed "${pkg}" && state="ON"
        args+=("${pkg}" "${label}${suffix}" "${state}")
    done

    list_height="${#TOOL_PACKAGES[@]}"
    ((list_height > 12)) && list_height=12
    height=$((list_height + 8))
    width=72

    local result
    result="$(whiptail --title "Basic Tools Installer" \
        --checklist "Space=select, Enter=OK, Esc=Cancel" \
        "${height}" "${width}" "${list_height}" \
        "${args[@]}" \
        3>&1 1>&2 2>&3)" || {
        log_info "Cancelled."
        return 0
    }

    # shellcheck disable=SC2206
    local selected=(${result})
    local -a to_install=()
    for pkg in "${selected[@]}"; do
        pkg="${pkg//\"/}"
        [[ -n "${pkg}" ]] && to_install+=("${pkg}")
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_warn "Nothing selected."
        return 0
    fi

    if confirm "Install ${#to_install[@]} selected tool(s)?"; then
        install_basic_tool_packages "${to_install[@]}"
    fi
}

run_basic_tools_installer() {
    if ! load_basic_tools_list; then
        return 1
    fi

    if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
        run_tools_whiptail_menu
    else
        run_tools_checkbox_menu
    fi
}
