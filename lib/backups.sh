#!/usr/bin/env bash
# Extensible backup / restore framework
#
# Register targets via config/backup-targets.list or:
#   backups_register "id" "Display name" "/path/to/file" "backup_label"
# Optional custom handlers:
#   backups_register_fn "id" backup_fn_name restore_fn_name
#
# Drop-in extension: modules/*/backup_targets.sh (auto-sourced on menu open)

BACKUPS_TARGETS_FILE="${TOOL_ROOT}/config/backup-targets.list"

declare -a BK_IDS=()
declare -A BK_NAMES=()
declare -A BK_PATHS=()
declare -A BK_LABELS=()
declare -A BK_BACKUP_FN=()
declare -A BK_RESTORE_FN=()

backups_register() {
    local id="$1"
    local name="$2"
    local path="$3"
    local label="${4:-${id}}"

    if [[ -z "${id}" || -z "${path}" ]]; then
        log_warn "backups_register: id and path required"
        return 1
    fi

    # Replace if re-registered
    local existing=0 i
    for i in "${BK_IDS[@]+"${BK_IDS[@]}"}"; do
        if [[ "${i}" == "${id}" ]]; then
            existing=1
            break
        fi
    done
    if [[ "${existing}" -eq 0 ]]; then
        BK_IDS+=("${id}")
    fi

    BK_NAMES["${id}"]="${name:-${id}}"
    BK_PATHS["${id}"]="${path}"
    BK_LABELS["${id}"]="${label}"
}

backups_register_fn() {
    local id="$1"
    local backup_fn="${2:-}"
    local restore_fn="${3:-}"
    [[ -z "${id}" ]] && return 1
    [[ -n "${backup_fn}" ]] && BK_BACKUP_FN["${id}"]="${backup_fn}"
    [[ -n "${restore_fn}" ]] && BK_RESTORE_FN["${id}"]="${restore_fn}"
}

backups_clear_registry() {
    BK_IDS=()
    BK_NAMES=()
    BK_PATHS=()
    BK_LABELS=()
    BK_BACKUP_FN=()
    BK_RESTORE_FN=()
}

backups_load_targets_file() {
    local file="${1:-${BACKUPS_TARGETS_FILE}}"
    [[ -f "${file}" ]] || return 0

    local line id name path label
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "${line}" ]] && continue

        IFS='|' read -r id name path label <<< "${line}"
        id="$(echo "${id}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        name="$(echo "${name}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        path="$(echo "${path}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        label="$(echo "${label}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "${label}" ]] && label="${id}"

        backups_register "${id}" "${name}" "${path}" "${label}"
    done < "${file}"
}

backups_load_module_extensions() {
    local modules_dir="${TOOL_ROOT}/modules"
    local f
    [[ -d "${modules_dir}" ]] || return 0

    while IFS= read -r -d '' f; do
        # shellcheck source=/dev/null
        source "${f}"
    done < <(find "${modules_dir}" -mindepth 2 -maxdepth 2 -name 'backup_targets.sh' -print0 2>/dev/null | sort -z)
}

backups_init_registry() {
    backups_clear_registry
    backups_load_targets_file
    backups_load_module_extensions

    # Built-in: full apt-repo status restore (disabled files + originals)
    # Not a path target — exposed as restore-all companion only
}

backups_target_exists() {
    local id="$1"
    local path="${BK_PATHS[${id}]:-}"
    [[ -n "${path}" && -e "${path}" ]]
}

backups_original_path() {
    local id="$1"
    echo "${IITD_BACKUP_DIR}/${BK_LABELS[${id}]}.original"
}

backups_has_any_backup() {
    local id="$1"
    local label="${BK_LABELS[${id}]}"
    [[ -f "${IITD_BACKUP_DIR}/${label}.original" ]] && return 0
    compgen -G "${IITD_BACKUP_DIR}/${label}.*.bak" >/dev/null 2>&1
}

backups_latest_bak() {
    local id="$1"
    local label="${BK_LABELS[${id}]}"
    local latest=""
    local f

    shopt -s nullglob
    for f in "${IITD_BACKUP_DIR}/${label}".*.bak; do
        [[ -f "${f}" ]] || continue
        if [[ -z "${latest}" || "${f}" -nt "${latest}" ]]; then
            latest="${f}"
        fi
    done
    shopt -u nullglob

    [[ -n "${latest}" ]] && echo "${latest}"
}

# --- Generic backup / restore for path targets ---

backups_backup_one() {
    local id="$1"
    local path="${BK_PATHS[${id}]:-}"
    local label="${BK_LABELS[${id}]:-}"
    local name="${BK_NAMES[${id}]:-${id}}"

    require_root
    init_iitd_data_dirs

    if [[ -n "${BK_BACKUP_FN[${id}]:-}" ]]; then
        "${BK_BACKUP_FN[${id}]}" "${id}"
        return $?
    fi

    if [[ -z "${path}" ]]; then
        log_error "Unknown backup target: ${id}"
        return 1
    fi

    if [[ ! -e "${path}" ]]; then
        log_warn "Skip backup (${name}): not found — ${path}"
        return 1
    fi

    _save_original_once "${path}" "${label}"
    _backup_timestamped "${path}" "${label}" >/dev/null
    log_success "Backed up: ${name} → ${IITD_BACKUP_DIR}/${label}.*"
    return 0
}

backups_restore_one() {
    local id="$1"
    local from_file="${2:-}"  # optional explicit snapshot path
    local path="${BK_PATHS[${id}]:-}"
    local label="${BK_LABELS[${id}]:-}"
    local name="${BK_NAMES[${id}]:-${id}}"
    local src=""

    require_root
    init_iitd_data_dirs

    if [[ -n "${BK_RESTORE_FN[${id}]:-}" ]]; then
        "${BK_RESTORE_FN[${id}]}" "${id}" "${from_file}"
        return $?
    fi

    if [[ -z "${path}" ]]; then
        log_error "Unknown restore target: ${id}"
        return 1
    fi

    if [[ -n "${from_file}" ]]; then
        src="${from_file}"
    elif [[ -f "$(backups_original_path "${id}")" ]]; then
        src="$(backups_original_path "${id}")"
    else
        src="$(backups_latest_bak "${id}" || true)"
    fi

    if [[ -z "${src}" || ! -f "${src}" ]]; then
        log_warn "No backup found for: ${name} (${label})"
        return 1
    fi

    mkdir -p "$(dirname "${path}")"
    cp -a "${src}" "${path}"
    chmod 644 "${path}" 2>/dev/null || true
    log_success "Restored: ${name} ← $(basename "${src}")"
    return 0
}

backups_backup_all() {
    local id ok=0 fail=0 skipped=0

    require_root
    backups_init_registry

    if [[ ${#BK_IDS[@]} -eq 0 ]]; then
        log_warn "No backup targets registered"
        return 1
    fi

    echo
    log_info "Backing up all registered targets..."
    echo

    for id in "${BK_IDS[@]}"; do
        if ! backups_target_exists "${id}" && [[ -z "${BK_BACKUP_FN[${id}]:-}" ]]; then
            log_info "Skip (missing): ${BK_NAMES[${id}]} — ${BK_PATHS[${id}]}"
            ((skipped++)) || true
            continue
        fi
        if backups_backup_one "${id}"; then
            ((ok++)) || true
        else
            ((fail++)) || true
        fi
    done

    echo
    log_success "Backup all done. OK=${ok}  skipped=${skipped}  failed=${fail}"
}

backups_restore_all() {
    local id ok=0 fail=0 skipped=0

    require_root
    backups_init_registry

    if ! confirm "Restore ALL registered backups and re-enable disabled apt repos?"; then
        log_info "Cancelled."
        return 0
    fi

    echo
    log_info "Restoring all registered targets..."
    echo

    for id in "${BK_IDS[@]}"; do
        if ! backups_has_any_backup "${id}" && [[ -z "${BK_RESTORE_FN[${id}]:-}" ]]; then
            log_info "Skip (no backup): ${BK_NAMES[${id}]}"
            ((skipped++)) || true
            continue
        fi
        if backups_restore_one "${id}"; then
            ((ok++)) || true
        else
            ((fail++)) || true
        fi
    done

    # Also re-enable disabled third-party / official sources renamed by this tool
    echo
    log_info "Re-enabling disabled apt list files (if any)..."
    backups_reenable_disabled_apt || true

    echo
    log_success "Restore all done. OK=${ok}  skipped=${skipped}  failed=${fail}"
}

backups_reenable_disabled_apt() {
    # Lightweight companion to path-target restores (does not prompt)
    require_root
    init_iitd_data_dirs

    local official_name="${SOURCES_LIST_D}/$(official_sources_filename 2>/dev/null || echo ubuntu.sources)"
    if [[ -f "${official_name}.disabled" && ! -f "${official_name}" ]]; then
        mv "${official_name}.disabled" "${official_name}"
        log_success "Re-enabled ${official_name}"
    fi
    if [[ -f "${UBUNTU_SOURCES}.disabled" && ! -f "${UBUNTU_SOURCES}" ]]; then
        mv "${UBUNTU_SOURCES}.disabled" "${UBUNTU_SOURCES}"
        log_success "Re-enabled ${UBUNTU_SOURCES}"
    fi
    if [[ -f "${DEBIAN_SOURCES}.disabled" && ! -f "${DEBIAN_SOURCES}" ]]; then
        mv "${DEBIAN_SOURCES}.disabled" "${DEBIAN_SOURCES}"
        log_success "Re-enabled ${DEBIAN_SOURCES}"
    fi

    local f base
    if [[ -f "${IITD_REPO_MANIFEST}" ]]; then
        local line key value
        while IFS= read -r line || [[ -n "${line}" ]]; do
            key="${line%%=*}"
            value="${line#*=}"
            if [[ "${key}" == "third_party" && -f "${value}.disabled" && ! -f "${value}" ]]; then
                mv "${value}.disabled" "${value}"
                log_success "Re-enabled ${value}"
            fi
        done < "${IITD_REPO_MANIFEST}"
    fi

    shopt -s nullglob
    for f in "${SOURCES_LIST_D}"/*.disabled; do
        [[ -f "${f}" ]] || continue
        base="${f%.disabled}"
        if [[ ! -f "${base}" ]]; then
            mv "${f}" "${base}"
            log_success "Re-enabled ${base}"
        fi
    done
    shopt -u nullglob
}

# --- List / pick helpers ---

backups_list_files() {
    init_iitd_data_dirs

    if [[ ! -d "${IITD_BACKUP_DIR}" ]]; then
        log_warn "Backup directory missing: ${IITD_BACKUP_DIR}"
        return 1
    fi

    local count
    count="$(find "${IITD_BACKUP_DIR}" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${count}" -eq 0 ]]; then
        log_info "No backup files in ${IITD_BACKUP_DIR}"
        return 1
    fi

    echo "  Directory: ${IITD_BACKUP_DIR}"
    echo
    if find "${IITD_BACKUP_DIR}" -maxdepth 1 -type f -printf '' >/dev/null 2>&1; then
        find "${IITD_BACKUP_DIR}" -maxdepth 1 -type f -printf '  %f\t%s bytes\t%TY-%Tm-%Td %TH:%TM\n' \
            | sort
    else
        ls -lah "${IITD_BACKUP_DIR}" | sed 's/^/  /'
    fi

    if [[ -f "${IITD_REPO_MANIFEST}" ]]; then
        echo
        echo -e "${BOLD}Manifest:${NC} ${IITD_REPO_MANIFEST}"
        sed 's/^/  /' "${IITD_REPO_MANIFEST}" 2>/dev/null || true
    fi

    return 0
}

backups_print_targets() {
    local i=1 id status
    for id in "${BK_IDS[@]}"; do
        status=""
        if backups_target_exists "${id}"; then
            status="${GREEN}[present]${NC}"
        else
            status="${YELLOW}[missing]${NC}"
        fi
        if backups_has_any_backup "${id}"; then
            status="${status} ${CYAN}[has backup]${NC}"
        fi
        echo -e "  ${BOLD}${i})${NC} ${BK_NAMES[${id}]}  ${status}"
        echo -e "     id=${id}  path=${BK_PATHS[${id}]}"
        ((i++)) || true
    done
}

backups_pick_target() {
    # prints selected id to stdout; returns 1 on cancel
    local prompt="${1:-Select target}"
    local choice i id

    if [[ ${#BK_IDS[@]} -eq 0 ]]; then
        log_warn "No targets registered" >&2
        return 1
    fi

    backups_print_targets >&2
    echo >&2
    read -r -p "${prompt} [1-${#BK_IDS[@]}, b]: " choice

    if [[ "${choice}" == "b" || "${choice}" == "B" || "${choice}" == "q" || "${choice}" == "Q" ]]; then
        return 1
    fi
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BK_IDS[@]} )); then
        log_warn "Invalid choice: ${choice}" >&2
        return 1
    fi

    echo "${BK_IDS[$((choice - 1))]}"
}

backups_pick_snapshot_for_target() {
    # For restore particular — choose original or a specific .bak
    local id="$1"
    local label="${BK_LABELS[${id}]}"
    local -a snaps=()
    local f choice

    if [[ -f "${IITD_BACKUP_DIR}/${label}.original" ]]; then
        snaps+=("${IITD_BACKUP_DIR}/${label}.original")
    fi

    shopt -s nullglob
    for f in "${IITD_BACKUP_DIR}/${label}".*.bak; do
        [[ -f "${f}" ]] && snaps+=("${f}")
    done
    shopt -u nullglob

    if [[ ${#snaps[@]} -eq 0 ]]; then
        log_warn "No snapshots for ${BK_NAMES[${id}]}" >&2
        return 1
    fi

    echo -e "${BOLD}Snapshots for ${BK_NAMES[${id}]}:${NC}" >&2
    local i=1
    for f in "${snaps[@]}"; do
        echo "  ${i}) $(basename "${f}")" >&2
        ((i++)) || true
    done
    echo >&2
    read -r -p "Select snapshot [1-${#snaps[@]}, b]: " choice

    if [[ "${choice}" == "b" || "${choice}" == "B" ]]; then
        return 1
    fi
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#snaps[@]} )); then
        log_warn "Invalid choice" >&2
        return 1
    fi

    echo "${snaps[$((choice - 1))]}"
}

backups_backup_particular() {
    local id

    backups_init_registry
    echo
    echo -e "${BOLD}Backup particular file / config${NC}"
    echo
    id="$(backups_pick_target "Backup which target")" || {
        log_info "Cancelled."
        return 0
    }

    echo
    if confirm "Backup ${BK_NAMES[${id}]} now?"; then
        backups_backup_one "${id}" || true
    else
        log_info "Cancelled."
    fi
}

backups_restore_particular() {
    local id snap

    backups_init_registry
    echo
    echo -e "${BOLD}Restore particular file / config${NC}"
    echo
    id="$(backups_pick_target "Restore which target")" || {
        log_info "Cancelled."
        return 0
    }

    echo
    snap="$(backups_pick_snapshot_for_target "${id}")" || {
        log_info "Cancelled."
        return 0
    }

    echo
    if confirm "Restore ${BK_NAMES[${id}]} from $(basename "${snap}")?"; then
        backups_restore_one "${id}" "${snap}" || true
    else
        log_info "Cancelled."
    fi
}

# --- Menu ---

show_backups_submenu() {
    clear
    echo -e "${BOLD}${CYAN}Backups & Restore${NC}"
    echo
    print_system_info
    print_iitd_paths_info
    echo
    echo -e "${BOLD}Submenu:${NC}"
    echo "  1) Backup all registered targets"
    echo "  2) Restore all backed-up files & config"
    echo "  3) Backup particular file / config"
    echo "  4) Restore particular file / config"
    echo "  5) List / show backup files"
    echo "  6) Show registered targets"
    echo
    echo "  Tip: add targets in config/backup-targets.list"
    echo "       or modules/<name>/backup_targets.sh"
    echo
    echo "  b) Back to main menu"
    echo
}

run_backups_menu() {
    local choice

    backups_init_registry

    while true; do
        show_backups_submenu
        read -r -p "Select option [1-6, b]: " choice

        case "${choice}" in
            1)
                echo
                if confirm "Backup ALL registered targets that exist on this system?"; then
                    backups_backup_all || true
                else
                    log_info "Cancelled."
                fi
                echo
                backups_list_files || true
                pause
                ;;
            2)
                echo
                backups_restore_all || true
                echo
                backups_list_files || true
                pause
                ;;
            3)
                backups_backup_particular || true
                pause
                ;;
            4)
                backups_restore_particular || true
                pause
                ;;
            5)
                echo
                backups_list_files || true
                pause
                ;;
            6)
                echo
                backups_init_registry
                echo -e "${BOLD}Registered targets (${#BK_IDS[@]}):${NC}"
                echo
                backups_print_targets
                echo
                pause
                ;;
            b|B|q|Q)
                break
                ;;
            *)
                log_warn "Invalid choice: ${choice}"
                pause
                ;;
        esac
    done
}
