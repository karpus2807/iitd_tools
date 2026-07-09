#!/usr/bin/env bash
# System Python detection — uses only distro-managed /usr/bin interpreters.
# Ignores pyenv, conda, /usr/local, and other custom Python installs.

# Ordered list: first match wins (python3 preferred over python2)
SYSTEM_PYTHON_CANDIDATES=(
    /usr/bin/python3
    /usr/bin/python2.7
    /usr/bin/python2
    /usr/bin/python
)

is_distro_python() {
    local bin="$1"
    local real major

    [[ -n "${bin}" && -x "${bin}" ]] || return 1
    [[ "${bin}" == /usr/bin/* ]] || return 1

    real="$(readlink -f "${bin}" 2>/dev/null || true)"
    [[ -n "${real}" && -x "${real}" ]] || return 1
    [[ "${real}" == /usr/bin/* ]] || return 1

    major="$("${real}" -c 'import sys; print(sys.version_info[0])' 2>/dev/null || true)"
    [[ "${major}" == "2" || "${major}" == "3" ]] || return 1

    # When dpkg is available, require the binary to belong to an installed package
    if command -v dpkg-query >/dev/null 2>&1; then
        if ! dpkg-query -S "${bin}" >/dev/null 2>&1 && ! dpkg-query -S "${real}" >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}

find_system_python() {
    local bin real version major

    PYTHON_CMD=""
    PYTHON_VERSION=""
    PYTHON_MAJOR=""

    for bin in "${SYSTEM_PYTHON_CANDIDATES[@]}"; do
        if ! is_distro_python "${bin}"; then
            continue
        fi

        real="$(readlink -f "${bin}")"
        version="$("${real}" -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))' 2>/dev/null || true)"
        major="${version%%.*}"

        if [[ -z "${version}" ]]; then
            continue
        fi

        PYTHON_CMD="${real}"
        PYTHON_VERSION="${version}"
        PYTHON_MAJOR="${major}"
        export PYTHON_CMD PYTHON_VERSION PYTHON_MAJOR
        return 0
    done

    return 1
}

detect_python() {
    if find_system_python; then
        return 0
    fi

    log_error "System Python not found under /usr/bin (python3 or python2)."
    log_error "Custom Python installs (pyenv, conda, /usr/local, etc.) are ignored."
    return 1
}

python_package_name() {
    case "${PYTHON_MAJOR}" in
        3) echo "python3" ;;
        2) echo "python-minimal" ;;
        *) echo "python3" ;;
    esac
}

print_python_info() {
    if [[ -n "${PYTHON_CMD:-}" ]]; then
        echo -e "${BOLD}Python:${NC} ${PYTHON_CMD} (${PYTHON_VERSION}, system)"
    fi
}
