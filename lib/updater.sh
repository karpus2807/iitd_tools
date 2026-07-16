#!/usr/bin/env bash
# Tool updater — install / downgrade from GitHub (latest commits or releases)

IITD_GITHUB_REPO="${IITD_GITHUB_REPO:-karpus2807/iitd_tools}"
IITD_GITHUB_API="https://api.github.com/repos/${IITD_GITHUB_REPO}"
IITD_TOOL_VERSION_FILE="${IITD_STATE_DIR:-/var/lib/iitd-tool/state}/tool.version"

declare -a UPDATER_REFS=()
declare -a UPDATER_LABELS=()
declare -a UPDATER_SOURCES=()

updater_current_version() {
    if [[ -f "${IITD_TOOL_VERSION_FILE}" ]]; then
        cat "${IITD_TOOL_VERSION_FILE}"
        return 0
    fi
    echo "unknown"
}

updater_save_version() {
    local ref="$1"
    local label="${2:-}"
    init_iitd_data_dirs
    {
        echo "ref=${ref}"
        echo "label=${label}"
        echo "updated_at=$(date -Iseconds 2>/dev/null || date)"
        echo "repo=${IITD_GITHUB_REPO}"
    } > "${IITD_TOOL_VERSION_FILE}"
}

updater_http_get() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 -A "iitd-tool-updater" "${url}"
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O - --timeout=60 --user-agent="iitd-tool-updater" "${url}"
        return $?
    fi
    return 1
}

updater_http_download() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 300 -A "iitd-tool-updater" -o "${out}" "${url}"
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=300 --user-agent="iitd-tool-updater" -O "${out}" "${url}"
        return $?
    fi
    return 1
}

# Prefer releases, then tags, then commits (latest 5)
updater_fetch_candidates() {
    UPDATER_REFS=()
    UPDATER_LABELS=()
    UPDATER_SOURCES=()

    local py
    py="$(command -v python3 || command -v python || true)"
    if [[ -z "${py}" ]]; then
        log_error "Python required to parse GitHub API JSON"
        return 1
    fi

    local json=""
    local kind=""

    if json="$(updater_http_get "${IITD_GITHUB_API}/releases?per_page=5" 2>/dev/null)" \
        && echo "${json}" | "${py}" -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if isinstance(d,list) and len(d)>0 else 1)' 2>/dev/null; then
        kind="release"
    elif json="$(updater_http_get "${IITD_GITHUB_API}/tags?per_page=5" 2>/dev/null)" \
        && echo "${json}" | "${py}" -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if isinstance(d,list) and len(d)>0 else 1)' 2>/dev/null; then
        kind="tag"
    elif json="$(updater_http_get "${IITD_GITHUB_API}/commits?per_page=5" 2>/dev/null)"; then
        kind="commit"
    else
        log_error "Could not reach GitHub API (${IITD_GITHUB_API}). Check network/proxy."
        return 1
    fi

    local parsed
    parsed="$(
        echo "${json}" | "${py}" -c '
import json, sys
kind = "'"${kind}"'"
data = json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit(1)
for item in data[:5]:
    if kind == "release":
        ref = item.get("tag_name") or ""
        name = item.get("name") or ref
        date = (item.get("published_at") or "")[:10]
        label = "%s — %s" % (ref, name)
        if date:
            label = "%s (%s)" % (label, date)
        out_ref = ref
    elif kind == "tag":
        ref = item.get("name") or ""
        sha = ((item.get("commit") or {}).get("sha") or "")[:7]
        label = "%s (%s)" % (ref, sha) if sha else ref
        out_ref = ref
    else:
        full = item.get("sha") or ""
        msg = ((item.get("commit") or {}).get("message") or "").split("\n")[0][:72]
        date = (((item.get("commit") or {}).get("author") or {}).get("date") or "")[:10]
        short = full[:7]
        label = "%s — %s" % (short, msg)
        if date:
            label = "%s [%s]" % (label, date)
        out_ref = full
    if out_ref:
        sys.stdout.write("%s\t%s\t%s\n" % (out_ref, label, kind))
'
    )" || {
        log_error "Failed to parse GitHub ${kind} list"
        return 1
    }

    local ref label src
    while IFS=$'\t' read -r ref label src; do
        [[ -z "${ref}" ]] && continue
        UPDATER_REFS+=("${ref}")
        UPDATER_LABELS+=("${label}")
        UPDATER_SOURCES+=("${src}")
    done <<< "${parsed}"

    if [[ ${#UPDATER_REFS[@]} -eq 0 ]]; then
        log_error "No updates found on GitHub"
        return 1
    fi

    log_info "Source: GitHub ${kind}s (showing latest ${#UPDATER_REFS[@]})"
    return 0
}

updater_print_do_not_cancel() {
    echo
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║  WARNING: Do NOT cancel / interrupt this update  ║${NC}"
    echo -e "${BOLD}${YELLOW}║  Wait until install finishes completely.         ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo
}

updater_clean_tool_install() {
    init_iitd_data_dirs

    if [[ -d "${IITD_ETC_INSTALL}" ]]; then
        log_info "Cleaning old tool files at ${IITD_ETC_INSTALL}..."
        find "${IITD_ETC_INSTALL}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || \
            rm -rf "${IITD_ETC_INSTALL:?}"/*
    fi
    mkdir -p "${IITD_ETC_INSTALL}"

    find "${IITD_VAR_LIB}" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    find "${IITD_VAR_LIB}" -type f -name '*.pyc' -delete 2>/dev/null || true

    log_success "Old tool files cleaned (backups preserved at ${IITD_BACKUP_DIR})"
}

updater_install_from_ref() {
    local ref="$1"
    local label="${2:-${ref}}"
    local tmp archive extract_dir src_dir

    require_root

    updater_print_do_not_cancel

    if ! confirm "Install this version now? (${label})"; then
        log_info "Cancelled."
        return 0
    fi

    updater_print_do_not_cancel
    log_info "Downloading ${IITD_GITHUB_REPO}@${ref} ..."

    tmp="$(mktemp -d /tmp/iitd-tool-upd.XXXXXX)"
    archive="${tmp}/src.tar.gz"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN

    local url="https://github.com/${IITD_GITHUB_REPO}/archive/${ref}.tar.gz"
    if ! updater_http_download "${url}" "${archive}"; then
        log_error "Download failed: ${url}"
        log_info "If on campus, enable proxy first: iitd-proxy <role> <userid>"
        return 1
    fi

    extract_dir="${tmp}/extract"
    mkdir -p "${extract_dir}"
    if ! tar -xzf "${archive}" -C "${extract_dir}"; then
        log_error "Failed to extract archive"
        return 1
    fi

    src_dir="$(find "${extract_dir}" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -z "${src_dir}" || ! -f "${src_dir}/iitd-config" ]]; then
        log_error "Downloaded archive does not look like iitd_tool"
        return 1
    fi

    updater_clean_tool_install

    log_info "Installing new tool files..."
    _install_copy_tree "${src_dir}" "${IITD_ETC_INSTALL}"

    chmod +x "${IITD_ETC_INSTALL}/iitd-config" "${IITD_ETC_INSTALL}/iitd-tool" 2>/dev/null || true
    chmod +x "${IITD_ETC_INSTALL}/scripts/iitd-proxy" 2>/dev/null || true
    chmod +x "${IITD_ETC_INSTALL}/install-iitd-tool.sh" 2>/dev/null || true

    ln -sf "${IITD_ETC_INSTALL}/iitd-tool" "${IITD_BIN_LINK}"
    ln -sf "${IITD_ETC_INSTALL}/iitd-config" "${IITD_CONFIG_LINK}"

    init_iitd_data_dirs
    updater_save_version "${ref}" "${label}"

    log_success "Tool updated to: ${label}"
    echo
    echo -e "${BOLD}Preserved backups:${NC}"
    backups_list_files || log_info "(no backup files yet)"
    echo
    echo "New tool is at ${IITD_ETC_INSTALL}"
    echo "Run again: sudo iitd-tool"
    echo
    log_warn "If Proxy Setup was installed before, reopen menu → Proxy Setup to refresh if needed."
}

show_updater_submenu() {
    clear
    echo -e "${BOLD}${CYAN}Tool Updater (GitHub)${NC}"
    echo
    print_system_info
    echo -e "${BOLD}Repo:${NC} https://github.com/${IITD_GITHUB_REPO}"
    echo -e "${BOLD}Installed:${NC}"
    updater_current_version | sed 's/^/  /'
    echo
    echo -e "${BOLD}Latest updates (upgrade or downgrade):${NC}"
    echo

    local i current_ref=""
    if [[ -f "${IITD_TOOL_VERSION_FILE}" ]]; then
        current_ref="$(grep '^ref=' "${IITD_TOOL_VERSION_FILE}" 2>/dev/null | cut -d= -f2-)"
    fi

    for ((i = 0; i < ${#UPDATER_REFS[@]}; i++)); do
        local mark=""
        if [[ -n "${current_ref}" ]]; then
            if [[ "${UPDATER_REFS[i]}" == "${current_ref}" \
                || "${UPDATER_REFS[i]}" == "${current_ref}"* \
                || "${current_ref}" == "${UPDATER_REFS[i]}"* ]]; then
                mark=" ${GREEN}[current]${NC}"
            fi
        fi
        echo -e "  ${BOLD}$((i + 1)))${NC} ${UPDATER_LABELS[i]}${mark}"
    done

    echo
    echo "  r) Refresh list from GitHub"
    echo "  b) Back to main menu"
    echo
}

run_updater_menu() {
    require_root

    if ! updater_fetch_candidates; then
        pause
        return 1
    fi

    local choice
    while true; do
        show_updater_submenu
        read -r -p "Select update [1-${#UPDATER_REFS[@]}, r, b]: " choice

        case "${choice}" in
            b|B|q|Q)
                break
                ;;
            r|R)
                updater_fetch_candidates || true
                pause
                ;;
            *)
                if [[ "${choice}" =~ ^[0-9]+$ ]] \
                    && (( choice >= 1 && choice <= ${#UPDATER_REFS[@]} )); then
                    local idx=$((choice - 1))
                    echo
                    updater_install_from_ref "${UPDATER_REFS[idx]}" "${UPDATER_LABELS[idx]}" || true
                    pause
                    log_info "Prefer restarting the tool menu after an update."
                else
                    log_warn "Invalid choice: ${choice}"
                    pause
                fi
                ;;
        esac
    done
}
