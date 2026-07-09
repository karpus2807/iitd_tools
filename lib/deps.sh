#!/usr/bin/env bash
# Dependency checks and warmup — runs at tool startup.

DEPS_MANIFEST="${TOOL_ROOT}/config/dependencies.list"
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
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_APT_PACKAGES[@]}"

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

    # Refresh Python path after package install
    find_system_python >/dev/null 2>&1 || true
    return 0
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

    install_missing_apt_packages || true

    # Re-check after possible install
    if [[ ${#MISSING_APT_PACKAGES[@]} -gt 0 ]]; then
        collect_missing_apt_packages
    fi

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

run_iitd_proxy_shell() {
    local launcher="${TOOL_ROOT}/scripts/iitd-proxy"

    if [[ -x "${launcher}" ]]; then
        "${launcher}" shell
        return $?
    fi

    if [[ -n "${PYTHON_CMD:-}" && -f "${TOOL_ROOT}/scripts/iitd-proxy.py" ]]; then
        "${PYTHON_CMD}" "${TOOL_ROOT}/scripts/iitd-proxy.py" shell
        return $?
    fi

    log_error "Cannot start IITD proxy shell — Python or script unavailable."
    return 1
}

run_failsafe_recovery() {
    echo
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║          FAILSAFE MODE                   ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════╝${NC}"
    echo
    log_warn "Required dependencies are missing."
    log_info "Starting IITD proxy shell to enable network access..."
    log_info "Type 'exit' at Role/Userid prompt to close the tool."
    echo

    run_iitd_proxy_shell
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

    detect_ubuntu
    detect_python 2>/dev/null || true
    warmup_dependencies

    if deps_tool_files_missing; then
        log_error "Critical tool files are missing. Reinstall or restore the tool directory."
        exit 1
    fi

    if deps_require_failsafe; then
        if [[ "${EUID}" -ne 0 ]]; then
            log_error "Dependencies missing. Re-run with: sudo ./iitd-config"
            exit 1
        fi

        if [[ "${attempt}" -ge 1 ]]; then
            log_error "Failsafe recovery did not resolve all dependencies."
            exit 1
        fi

        if ! run_failsafe_recovery; then
            exit 1
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
