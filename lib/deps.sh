#!/usr/bin/env bash
# Dependency checks and warmup — runs at tool startup.

DEPS_MANIFEST="${TOOL_ROOT}/config/dependencies.list"
IITD_REPO_URL="http://repo.iitd.ernet.in/ubuntu/"
DEPS_STATUS="ok"
DEPS_WARNINGS=0

deps_warn() {
    log_warn "$*"
    DEPS_STATUS="warnings"
    ((DEPS_WARNINGS++)) || true
}

deps_fail() {
    log_error "$*"
    DEPS_STATUS="failed"
    ((DEPS_WARNINGS++)) || true
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

read_dependency_manifest() {
    DEPS_APT_PACKAGES=()
    DEPS_TOOL_FILES=()

    if [[ ! -f "${DEPS_MANIFEST}" ]]; then
        deps_fail "Dependency manifest missing: ${DEPS_MANIFEST}"
        return 1
    fi

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "${line}" ]] && continue

        key="${line%%:*}"
        value="${line#*:}"

        case "${key}" in
            pkg) DEPS_APT_PACKAGES+=("${value}") ;;
            file) DEPS_TOOL_FILES+=("${value}") ;;
            *)
                deps_warn "Unknown manifest entry: ${line}"
                ;;
        esac
    done < "${DEPS_MANIFEST}"
}

check_tool_files() {
    local rel path
    local missing=0

    for rel in "${DEPS_TOOL_FILES[@]}"; do
        path="${TOOL_ROOT}/${rel}"
        if [[ -f "${path}" ]]; then
            log_success "File: ${rel}"
        else
            deps_fail "Missing tool file: ${rel}"
            missing=1
        fi
    done

    [[ "${missing}" -eq 0 ]]
}

check_system_commands() {
    local cmd
    local -a required_cmds=(sed sort find apt-get dpkg-query)

    for cmd in "${required_cmds[@]}"; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            log_success "Command: ${cmd}"
        else
            deps_warn "Command not found: ${cmd}"
        fi
    done
}

check_python_stdlib() {
    if [[ -z "${PYTHON_CMD:-}" ]]; then
        deps_warn "Python not available — skipping Python module checks"
        return 1
    fi

    if check_python_stdlib_silent; then
        log_success "Python stdlib modules (iitd-proxy requirements)"
        return 0
    fi

    deps_fail "Python module check failed for ${PYTHON_CMD}"
    return 1
}

check_python_stdlib_silent() {
    if [[ -z "${PYTHON_CMD:-}" ]]; then
        return 1
    fi

    "${PYTHON_CMD}" -c '
from __future__ import print_function
import sys

required = [
    "argparse", "getpass", "io", "json", "os", "pwd", "shutil",
    "socket", "ssl", "subprocess", "time",
]

if sys.version_info[0] >= 3:
    required.extend(["urllib.request", "urllib.parse", "urllib.error", "html.parser"])
else:
    required.extend(["urllib2", "urlparse", "HTMLParser"])

for name in required:
    try:
        if sys.version_info[0] >= 3 and "." in name:
            __import__(name, fromlist=["_"])
        else:
            __import__(name)
    except Exception:
        sys.exit(1)
' >/dev/null 2>&1
}

collect_missing_apt_packages() {
    MISSING_APT_PACKAGES=()
    local pkg py_pkg

    for pkg in "${DEPS_APT_PACKAGES[@]}"; do
        if ! package_installed "${pkg}"; then
            MISSING_APT_PACKAGES+=("${pkg}")
        fi
    done

    if [[ -n "${PYTHON_MAJOR:-}" ]]; then
        py_pkg="$(python_package_name)"
        if ! package_installed "${py_pkg}"; then
            MISSING_APT_PACKAGES+=("${py_pkg}")
        fi
    elif ! package_installed "python3" && ! package_installed "python-minimal"; then
        MISSING_APT_PACKAGES+=("python3")
    fi
}

check_apt_packages() {
    collect_missing_apt_packages

    local pkg
    for pkg in "${DEPS_APT_PACKAGES[@]}"; do
        if package_installed "${pkg}"; then
            log_success "Package: ${pkg}"
        else
            log_warn "Package missing: ${pkg}"
        fi
    done

    if [[ -n "${PYTHON_MAJOR:-}" ]]; then
        pkg="$(python_package_name)"
        if package_installed "${pkg}"; then
            log_success "Package: ${pkg}"
        else
            log_warn "Package missing: ${pkg}"
        fi
    fi
}

install_missing_apt_packages() {
    collect_missing_apt_packages

    if [[ ${#MISSING_APT_PACKAGES[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ "${EUID}" -ne 0 ]]; then
        deps_warn "Run with sudo to auto-install: ${MISSING_APT_PACKAGES[*]}"
        return 1
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        deps_fail "apt-get not available — cannot install packages"
        return 1
    fi

    log_info "Installing missing packages: ${MISSING_APT_PACKAGES[*]}"
    if ! apt-get update -qq; then
        log_warn "apt-get update failed"
        return 1
    fi
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_APT_PACKAGES[@]}"; then
        log_warn "apt-get install failed"
        return 1
    fi

    local pkg still_missing=()
    for pkg in "${MISSING_APT_PACKAGES[@]}"; do
        if ! package_installed "${pkg}"; then
            still_missing+=("${pkg}")
        else
            log_success "Installed package: ${pkg}"
        fi
    done

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        deps_fail "Could not install: ${still_missing[*]}"
        return 1
    fi

    find_system_python >/dev/null 2>&1 || true
    return 0
}

check_internet_access() {
    if command -v curl >/dev/null 2>&1; then
        if [[ "${OS_ID:-ubuntu}" == "debian" ]]; then
            curl -fsS --max-time 10 http://deb.debian.org/debian/ >/dev/null 2>&1 && return 0
        else
            curl -fsS --max-time 10 http://connectivity-check.ubuntu.com/ >/dev/null 2>&1 && return 0
            curl -fsS --max-time 10 http://archive.ubuntu.com/ubuntu/ >/dev/null 2>&1 && return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if [[ "${OS_ID:-ubuntu}" == "debian" ]]; then
            wget -q --spider --timeout=10 http://deb.debian.org/debian/ 2>/dev/null && return 0
        else
            wget -q --spider --timeout=10 http://connectivity-check.ubuntu.com/ 2>/dev/null && return 0
        fi
    fi

    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && return 0
    return 1
}

check_iitd_repo_access() {
    local repo_url="${IITD_REPO_MIRROR_URL:-${IITD_REPO_URL}}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 15 "${repo_url}" >/dev/null 2>&1 && return 0
        curl -fsSI --max-time 15 "${repo_url}" >/dev/null 2>&1 && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout=15 "${repo_url}" 2>/dev/null && return 0
    fi

    return 1
}

try_direct_dependency_install() {
    read_dependency_manifest 2>/dev/null || true
    collect_missing_apt_packages

    if [[ ${#MISSING_APT_PACKAGES[@]} -eq 0 ]] \
        && [[ -n "${PYTHON_CMD:-}" ]] \
        && check_python_stdlib_silent; then
        return 0
    fi

    echo
    log_info "Step 1: Trying direct install (without proxy)..."
    echo

    local net_ok=0 repo_ok=0

    if check_internet_access; then
        log_success "Internet access: available"
        net_ok=1
    else
        log_warn "Internet access: not detected"
    fi

    if check_iitd_repo_access; then
        log_success "IITD repo reachable: ${IITD_REPO_MIRROR_URL:-${IITD_REPO_URL}}"
        repo_ok=1
    else
        log_warn "IITD repo not reachable: ${IITD_REPO_MIRROR_URL:-${IITD_REPO_URL}}"
    fi

    if [[ "${net_ok}" -eq 0 && "${repo_ok}" -eq 0 ]]; then
        log_warn "No direct network path — proxy failsafe will be used next."
        return 1
    fi

    if install_missing_apt_packages; then
        find_system_python >/dev/null 2>&1 || true
        collect_missing_apt_packages
        if [[ ${#MISSING_APT_PACKAGES[@]} -eq 0 ]] \
            && { [[ -z "${PYTHON_CMD:-}" ]] || check_python_stdlib_silent; }; then
            log_success "Dependencies installed directly (no proxy needed)."
            DEPS_STATUS="ok"
            return 0
        fi
    fi

    log_warn "Direct install incomplete — will try proxy failsafe next."
    return 1
}

warmup_dependencies() {
    DEPS_STATUS="ok"
    DEPS_WARNINGS=0
    MISSING_APT_PACKAGES=()

    echo
    echo -e "${BOLD}${CYAN}Warming up — checking dependencies...${NC}"
    echo

    read_dependency_manifest || true

    check_tool_files || true
    check_system_commands
    check_apt_packages

    detect_python 2>/dev/null || deps_warn "System Python not found in /usr/bin"
    check_python_stdlib || true

    echo
    case "${DEPS_STATUS}" in
        ok)
            log_success "Warmup complete — all dependencies OK"
            ;;
        warnings)
            log_warn "Warmup complete with ${DEPS_WARNINGS} warning(s)"
            ;;
        failed)
            log_error "Warmup finished with critical dependency issue(s)"
            ;;
    esac
    echo

    export DEPS_STATUS DEPS_WARNINGS
}

deps_tool_files_missing() {
    local rel path
    read_dependency_manifest 2>/dev/null || true
    for rel in "${DEPS_TOOL_FILES[@]}"; do
        path="${TOOL_ROOT}/${rel}"
        if [[ ! -f "${path}" ]]; then
            return 0
        fi
    done
    return 1
}

deps_require_failsafe() {
    read_dependency_manifest 2>/dev/null || true
    collect_missing_apt_packages

    if [[ ${#MISSING_APT_PACKAGES[@]} -gt 0 ]]; then
        return 0
    fi

    if [[ -z "${PYTHON_CMD:-}" ]]; then
        return 0
    fi

    if ! check_python_stdlib_silent; then
        return 0
    fi

    return 1
}

run_iitd_proxy_cmd() {
    local py_script="${TOOL_ROOT}/scripts/iitd-proxy.py"
    local installed_py="/usr/local/lib/iitd-tool/iitd-proxy.py"

    if [[ -z "${PYTHON_CMD:-}" ]]; then
        detect_python 2>/dev/null || find_system_python 2>/dev/null || true
    fi

    if [[ -z "${PYTHON_CMD:-}" ]]; then
        return 127
    fi

    if [[ -f "${py_script}" ]]; then
        "${PYTHON_CMD}" "${py_script}" "$@"
        return $?
    fi

    if [[ -f "${installed_py}" ]]; then
        "${PYTHON_CMD}" "${installed_py}" "$@"
        return $?
    fi

    return 127
}

run_staff_proxy_login() {
    if ! run_iitd_proxy_cmd staff-login; then
        local rc=$?
        if [[ "${rc}" -eq 127 ]]; then
            log_error "System Python / iitd-proxy.py not found — cannot run staff proxy login."
        fi
        return "${rc}"
    fi
    return 0
}

campus_proxy_already_active() {
    # Exit 0 from check-active => previous login left system config on disk
    run_iitd_proxy_cmd check-active >/dev/null 2>&1
}

ensure_staff_campus_proxy() {
    echo
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     IITD Staff Proxy Login (required)    ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo

    # Prefer verified TLS: install bundled ca-chain if missing
    if declare -f ssl_ca_chain_is_installed >/dev/null 2>&1; then
        if ! ssl_ca_chain_is_installed; then
            local src=""
            if src="$(ssl_ca_chain_source_path 2>/dev/null)"; then
                log_info "Installing bundled ca-chain for TLS verification..."
                ssl_ca_chain_apply "${src}" 1 || log_warn "ca-chain install skipped/failed"
            fi
        fi
    fi

    if [[ -z "${PYTHON_CMD:-}" ]]; then
        detect_python 2>/dev/null || true
    fi

    if [[ -z "${PYTHON_CMD:-}" ]]; then
        log_info "Trying to install system Python for proxy login..."
        apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3 2>/dev/null \
            || DEBIAN_FRONTEND=noninteractive apt-get install -y python-minimal 2>/dev/null \
            || true
        detect_python 2>/dev/null || find_system_python 2>/dev/null || true
    fi

    # Already logged in (config on disk) → do not ask password again
    local active_msg=""
    if active_msg="$(run_iitd_proxy_cmd check-active 2>/dev/null)"; then
        log_success "$(echo "${active_msg}" | tail -n 1)"
        log_info "To force re-login: sudo iitd-proxy logout && sudo iitd-tool"
        return 0
    fi

    log_info "Only staff userid + password. Configures campus proxy system-wide."
    echo

    local rc=1
    while true; do
        run_staff_proxy_login
        rc=$?
        if [[ "${rc}" -eq 0 ]]; then
            log_success "Staff proxy enabled system-wide."
            return 0
        fi
        if [[ "${rc}" -eq 2 ]]; then
            log_error "Staff proxy login cancelled."
            return 1
        fi
        if [[ "${rc}" -eq 127 ]]; then
            return 1
        fi
        log_warn "Staff proxy login failed."
        if ! confirm "Retry staff proxy login?"; then
            return 1
        fi
    done
}

run_iitd_proxy_shell() {
    # Failsafe / legacy: staff-only login (no free-form role shell that needs sudoers)
    run_staff_proxy_login
}

run_failsafe_recovery() {
    echo
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║          FAILSAFE MODE (PROXY)           ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════╝${NC}"
    echo
    log_warn "Direct install failed or unavailable."
    log_info "Step 2: Staff proxy login for dependency download..."
    echo

    run_staff_proxy_login
    local shell_rc=$?

    if [[ "${shell_rc}" -eq 2 ]]; then
        log_error "Proxy login skipped. Tool cannot run without dependencies."
        return 1
    fi

    if [[ "${shell_rc}" -ne 0 ]]; then
        log_error "Proxy login failed (exit ${shell_rc})."
        return 1
    fi

    log_success "Proxy enabled. Installing missing dependencies..."
    echo

    if ! install_missing_apt_packages; then
        log_error "Dependency installation failed even after proxy login."
        return 1
    fi

    find_system_python >/dev/null 2>&1 || true

    if ! check_python_stdlib_silent; then
        log_error "Python modules still unavailable after install."
        return 1
    fi

    log_success "Failsafe recovery complete."
    return 0
}

boot_tool() {
    local attempt="${1:-0}"

    if [[ "${EUID}" -ne 0 ]]; then
        log_error "IITD tool requires root. Run: sudo iitd-tool"
        exit 1
    fi

    detect_ubuntu
    detect_python 2>/dev/null || true

    # Campus network first: staff proxy so apt/tool/proxy work everywhere
    if [[ "${attempt}" -eq 0 ]]; then
        if ! ensure_staff_campus_proxy; then
            log_error "Staff proxy is required before the tool can continue."
            exit 1
        fi
        echo
    fi

    warmup_dependencies

    if deps_tool_files_missing; then
        log_error "Critical tool files are missing. Reinstall or restore the tool directory."
        exit 1
    fi

    if deps_require_failsafe; then
        if [[ "${attempt}" -ge 1 ]]; then
            log_error "Dependency recovery did not resolve all issues."
            exit 1
        fi

        try_direct_dependency_install || true

        if deps_require_failsafe; then
            if ! run_failsafe_recovery; then
                exit 1
            fi
        fi

        echo
        log_info "Restarting tool in normal mode..."
        echo
        boot_tool $((attempt + 1))
        return
    fi

    discover_modules
    run_main_menu
}

print_deps_info() {
    case "${DEPS_STATUS:-unknown}" in
        ok)
            echo -e "${BOLD}Dependencies:${NC} OK"
            ;;
        warnings)
            echo -e "${BOLD}Dependencies:${NC} ${YELLOW}${DEPS_WARNINGS} warning(s)${NC}"
            ;;
        failed)
            echo -e "${BOLD}Dependencies:${NC} ${RED}issues detected${NC}"
            ;;
        *)
            echo -e "${BOLD}Dependencies:${NC} not checked"
            ;;
    esac
}
