#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
IIT Delhi proxy helper for Ubuntu 16.04 through 26.04.
Compatible with Python 2.7 and Python 3.x.

  iitd-proxy <role> <userid>
  iitd-proxy logout
"""

from __future__ import print_function, unicode_literals

import argparse
import getpass
import io
import json
import os
import pwd
import shutil
import socket
import ssl
import subprocess
import sys
import time

PY3 = sys.version_info[0] >= 3
PY2 = not PY3

if PY3:
    import urllib.error
    import urllib.parse
    import urllib.request
    from html.parser import HTMLParser
    JSONDecodeError = json.JSONDecodeError
else:
    import urllib2
    import urlparse as urllib_parse
    from HTMLParser import HTMLParser
    JSONDecodeError = ValueError


PREFIX_MAP = {
    "btech": 22,
    "mtech": 62,
    "phd": 61,
    "staff": 78,
    "faculty": 82,
    "visitor": 21,
}

LOGIN_URL_MAP = {
    "staff": "https://proxy21.iitd.ac.in/cgi-bin/proxy.cgi",
    "faculty": "https://proxy82.iitd.ac.in/cgi-bin/proxy.cgi",
    "visitor": "https://proxy21.iitd.ac.in/cgi-bin/proxy.cgi",
}

PROXY_PORT = 3128
NO_PROXY = "localhost,127.0.0.1,::1"
MANAGED_MARKER = "iitd-proxy"

APT_PROXY_FILE = "/etc/apt/apt.conf.d/95iitd-proxy"
ENV_FILE = "/etc/environment"
PROFILE_FILE = "/etc/profile.d/iitd-proxy.sh"
SYSTEMD_PROXY_FILE = "/etc/systemd/system.conf.d/95iitd-proxy.conf"
SYSTEMD_USER_PROXY_FILE = "/etc/systemd/user.conf.d/95iitd-proxy.conf"
CHROME_POLICY_FILE = "/etc/opt/chrome/policies/managed/iitd-proxy.json"
CHROMIUM_POLICY_FILE = "/etc/chromium/policies/managed/iitd-proxy.json"
FIREFOX_POLICY_FILE = "/etc/firefox/policies/policies.json"
STATE_DIR = "/var/lib/iitd-proxy"
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOG_FILE = "/var/log/iitd-proxy.log"

BROWSER_DESKTOP_SOURCES = [
    "/usr/share/applications/google-chrome.desktop",
    "/usr/share/applications/google-chrome-stable.desktop",
    "/usr/share/applications/chromium-browser.desktop",
    "/usr/share/applications/chromium.desktop",
    "/usr/share/applications/chromium_chromium.desktop",
    "/usr/share/applications/firefox.desktop",
    "/usr/share/applications/firefox-esr.desktop",
]


class ProxyError(RuntimeError):
    pass


class CompletedProcess(object):
    def __init__(self, args, returncode, stdout=""):
        self.args = args
        self.returncode = returncode
        self.stdout = stdout


class SessionParser(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self)
        self.sessionid = None

    def handle_starttag(self, tag, attrs):
        if tag != "input":
            return
        data = dict(attrs)
        if data.get("name") == "sessionid":
            self.sessionid = data.get("value")


def path_join(*parts):
    return os.path.join(*parts)


def path_exists(path):
    return os.path.exists(path)


def read_text_file(path):
    with io.open(path, "r", encoding="utf-8", errors="ignore") as handle:
        return handle.read()


def write_text_file(path, content, mode=0o644):
    parent = os.path.dirname(path)
    if parent and not path_exists(parent):
        os.makedirs(parent)
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chmod(path, mode)


def mkdir_p(path):
    if not path_exists(path):
        os.makedirs(path)


def log(message):
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = "[{0}] {1}".format(stamp, message)
    print(message)
    try:
        mkdir_p(os.path.dirname(LOG_FILE))
        with io.open(LOG_FILE, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except (OSError, IOError):
        with io.open("/tmp/iitd-proxy.log", "a", encoding="utf-8") as handle:
            handle.write(line + "\n")


def decode_output(value):
    if value is None:
        return ""
    if PY2 and isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value


def run_cmd(cmd, check=True, timeout=None, env=None):
    log("+ " + " ".join(cmd))

    if PY3 and hasattr(subprocess, "run"):
        try:
            completed = subprocess.run(
                cmd,
                check=False,
                universal_newlines=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout,
                env=env,
            )
        except subprocess.TimeoutExpired as exc:
            output = decode_output(exc.stdout)
            if check:
                raise ProxyError("Command timed out: {0}".format(" ".join(cmd)))
            return CompletedProcess(cmd, 124, output)
        stdout = completed.stdout or ""
    else:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            universal_newlines=not PY2,
        )
        stdout, _ = proc.communicate()
        stdout = decode_output(stdout)
        completed = CompletedProcess(cmd, proc.returncode, stdout)

    if stdout.strip():
        for line in stdout.rstrip().splitlines():
            log("  " + line)
    if check and completed.returncode != 0:
        raise ProxyError(
            "Command failed ({0}): {1}".format(completed.returncode, " ".join(cmd))
        )
    return completed


def require_root():
    if os.geteuid() != 0:
        raise ProxyError(
            "Root required. After Proxy Setup install, run: iitd-proxy <role> <userid> "
            "(no sudo). Or ask an admin to reinstall iitd-proxy."
        )


def proxy_host(prefix):
    return "10.10.{0}.21".format(prefix)


def proxy_url(prefix):
    return "http://{0}:{1}/".format(proxy_host(prefix), PROXY_PORT)


def get_login_url(role, prefix):
    return LOGIN_URL_MAP.get(role, "https://proxy{0}.iitd.ac.in/cgi-bin/proxy.cgi".format(prefix))


def proxy_env(prefix):
    url = proxy_url(prefix)
    env = os.environ.copy()
    env.update(
        {
            "http_proxy": url,
            "https_proxy": url,
            "ftp_proxy": url,
            "HTTP_PROXY": url,
            "HTTPS_PROXY": url,
            "FTP_PROXY": url,
            "no_proxy": NO_PROXY,
            "NO_PROXY": NO_PROXY,
        }
    )
    return env


def target_user_record():
    user = os.environ.get("SUDO_USER")
    if not user or user == "root":
        return None
    try:
        return pwd.getpwnam(user)
    except KeyError:
        return None


def managed_block(content):
    return (
        "# >>> iitd-proxy managed >>>\n"
        + content.rstrip()
        + "\n# <<< iitd-proxy managed <<<\n"
    )


def replace_managed_block(path, content):
    marker_start = "# >>> iitd-proxy managed >>>"
    marker_end = "# <<< iitd-proxy managed <<<"
    new_block = managed_block(content)

    if path_exists(path):
        existing = read_text_file(path)
        start = existing.find(marker_start)
        end = existing.find(marker_end)
        if start != -1 and end != -1:
            end += len(marker_end)
            existing = existing[:start].rstrip() + "\n\n" + existing[end:].lstrip()
        final = existing.rstrip() + "\n\n" + new_block
    else:
        final = new_block

    write_text_file(path, final)


def remove_managed_block(path):
    marker_start = "# >>> iitd-proxy managed >>>"
    marker_end = "# <<< iitd-proxy managed <<<"
    if not path_exists(path):
        return

    existing = read_text_file(path)
    start = existing.find(marker_start)
    end = existing.find(marker_end)
    if start == -1 or end == -1:
        return

    end += len(marker_end)
    cleaned = (existing[:start].rstrip() + "\n" + existing[end:].lstrip()).strip()
    write_text_file(path, (cleaned + "\n") if cleaned else "")


def chown_to_user(path, user_info):
    try:
        os.chown(path, user_info.pw_uid, user_info.pw_gid)
    except (OSError, IOError) as exc:
        log("Could not change owner for {0}: {1}".format(path, exc))


def ensure_user_dir(path, user_info):
    mkdir_p(path)
    current = path
    home = user_info.pw_dir
    while current.startswith(home) and current != os.path.dirname(home):
        chown_to_user(current, user_info)
        if current == home:
            break
        current = os.path.dirname(current)


def direct_https_opener(verify_tls=True):
    if hasattr(ssl, "create_default_context"):
        sslctx = ssl.create_default_context() if verify_tls else ssl._create_unverified_context()
    else:
        sslctx = None

    if PY3:
        return urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=sslctx),
        )

    if sslctx is not None:
        https_handler = urllib2.HTTPSHandler(context=sslctx)
    else:
        https_handler = urllib2.HTTPSHandler()
    return urllib2.build_opener(urllib2.ProxyHandler({}), https_handler)


def urlopen_text(opener, url, data=None, timeout=20):
    if PY3:
        if data is not None:
            response = opener.open(url, data=data, timeout=timeout)
        else:
            response = opener.open(url, timeout=timeout)
        raw = response.read()
        if isinstance(raw, bytes):
            return raw.decode("utf-8", "replace")
        return raw

    if data is not None:
        request = urllib2.Request(url, data=data)
    else:
        request = urllib2.Request(url)
    raw = opener.open(request, timeout=timeout).read()
    if isinstance(raw, bytes):
        return raw.decode("utf-8", "replace")
    return raw


def is_certificate_error(exc):
    text = str(exc).lower()
    return (
        "certificate_verify_failed" in text
        or "certificate verify failed" in text
        or "ssl: certificate_verify_failed" in text
    )


LEGACY_IITD_CA_PATHS = (
    "/usr/local/share/ca-certificates/iitd-cciitd-ca.crt",
    "/usr/local/lib/iitd-tool/certs/CCIITD-CA.crt",
)


def remove_legacy_iitd_ca_files():
    """Remove old custom IITD CA files from a previous tool version."""
    removed = False

    for path in LEGACY_IITD_CA_PATHS:
        if path_exists(path):
            try:
                os.remove(path)
                log("Removed legacy IITD CA file: {0}".format(path))
                removed = True
            except (OSError, IOError) as exc:
                log("Could not remove legacy IITD CA file {0}: {1}".format(path, exc))

    certs_dir = "/usr/local/lib/iitd-tool/certs"
    if path_exists(certs_dir):
        try:
            if not os.listdir(certs_dir):
                os.rmdir(certs_dir)
        except (OSError, IOError):
            pass

    if removed and shutil.which("update-ca-certificates"):
        run_cmd(["update-ca-certificates"], check=False, timeout=60)


def urlopen_with_tls_fallback(url, data=None, timeout=20):
    """Try HTTPS with verification first; fall back without verification on TLS errors."""
    opener = direct_https_opener(verify_tls=True)

    try:
        return urlopen_text(opener, url, data=data, timeout=timeout)
    except Exception as exc:
        if not is_certificate_error(exc):
            raise
        log("TLS verification failed; retrying without certificate verification.")
        opener = direct_https_opener(verify_tls=False)
        return urlopen_text(opener, url, data=data, timeout=timeout)


def login(role, prefix, user, password):
    base = get_login_url(role, prefix)

    try:
        html = urlopen_with_tls_fallback(base)
    except Exception as exc:
        raise ProxyError("Could not reach IITD proxy login page: {0}".format(exc))

    parser = SessionParser()
    parser.feed(html)
    if not parser.sessionid:
        raise ProxyError("Session ID not found on IITD proxy login page.")

    form = {
        "sessionid": parser.sessionid,
        "action": "Validate",
        "userid": user,
        "pass": password,
    }

    if PY3:
        encoded = urllib.parse.urlencode(form).encode()
    else:
        encoded = urllib_parse.urlencode(form)

    try:
        response = urlopen_with_tls_fallback(base, data=encoded)
    except Exception as exc:
        raise ProxyError("IITD proxy login request failed: {0}".format(exc))

    lowered = response.lower()
    if "successfully" in lowered or "already logged in" in lowered:
        log("IITD proxy login: OK")
        return
    raise ProxyError("IITD proxy login failed. Check role, userid, and password.")


def configure_apt(prefix):
    url = proxy_url(prefix)
    content = (
        "// Managed by {0}. Remove with: iitd-proxy logout\n"
        'Acquire::http::Proxy "{1}";\n'
        'Acquire::https::Proxy "{1}";\n'
        'Acquire::ftp::Proxy "{1}";\n'
        'Acquire::Retries "3";\n'
    ).format(MANAGED_MARKER, url)
    write_text_file(APT_PROXY_FILE, content)


def quote_env_value(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def configure_environment(prefix):
    url = proxy_url(prefix)
    managed = [
        ("http_proxy", url),
        ("https_proxy", url),
        ("ftp_proxy", url),
        ("HTTP_PROXY", url),
        ("HTTPS_PROXY", url),
        ("FTP_PROXY", url),
        ("no_proxy", NO_PROXY),
        ("NO_PROXY", NO_PROXY),
    ]
    managed_keys = set(key for key, _ in managed)

    existing = []
    if path_exists(ENV_FILE):
        for line in read_text_file(ENV_FILE).splitlines():
            key = line.split("=", 1)[0].strip() if "=" in line else ""
            if key not in managed_keys:
                existing.append(line)

    existing.extend("{0}={1}".format(key, quote_env_value(value)) for key, value in managed)
    write_text_file(ENV_FILE, "\n".join(existing).rstrip() + "\n")
    log("Updated {0}".format(ENV_FILE))

    profile_lines = [
        "# Managed by {0}. Remove with: iitd-proxy logout".format(MANAGED_MARKER),
        "export http_proxy={0}".format(quote_env_value(url)),
        "export https_proxy={0}".format(quote_env_value(url)),
        "export ftp_proxy={0}".format(quote_env_value(url)),
        "export HTTP_PROXY={0}".format(quote_env_value(url)),
        "export HTTPS_PROXY={0}".format(quote_env_value(url)),
        "export FTP_PROXY={0}".format(quote_env_value(url)),
        "export no_proxy={0}".format(quote_env_value(NO_PROXY)),
        "export NO_PROXY={0}".format(quote_env_value(NO_PROXY)),
        "",
    ]
    write_text_file(PROFILE_FILE, "\n".join(profile_lines))


def configure_systemd(prefix):
    url = proxy_url(prefix)
    content = (
        "# Managed by {0}. Remove with: iitd-proxy logout\n"
        "[Manager]\n"
        'DefaultEnvironment="http_proxy={1}" "https_proxy={1}" "ftp_proxy={1}" '
        '"HTTP_PROXY={1}" "HTTPS_PROXY={1}" "FTP_PROXY={1}" '
        '"no_proxy={2}" "NO_PROXY={2}"\n'
    ).format(MANAGED_MARKER, url, NO_PROXY)
    write_text_file(SYSTEMD_PROXY_FILE, content)
    write_text_file(SYSTEMD_USER_PROXY_FILE, content)
    if shutil.which("systemctl"):
        run_cmd(["systemctl", "daemon-reexec"], check=False, timeout=15)


def configure_snap(prefix):
    if not shutil.which("snap"):
        log("Snap: not installed, skipping.")
        return "SKIPPED"

    url = proxy_url(prefix).rstrip("/")
    result = run_cmd(
        ["snap", "set", "system", "proxy.http={0}".format(url), "proxy.https={0}".format(url)],
        check=False,
        timeout=30,
    )
    if result.returncode != 0:
        log("Snap proxy could not be configured.")
        return "CHECK"

    if shutil.which("systemctl"):
        run_cmd(["systemctl", "restart", "snapd.service"], check=False, timeout=20)
    log("Snap Store proxy configured.")
    return "OK"


# GitHub-related hosts — explicit git proxy entries so clone/API/assets work on campus.
GITHUB_PROXY_HOSTS = (
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "gist.github.com",
    "ghcr.io",
    "npm.pkg.github.com",
)


def _git_proxy_keys():
    keys = ["http.proxy", "https.proxy"]
    for host in GITHUB_PROXY_HOSTS:
        keys.append("http.https://{0}/.proxy".format(host))
    return keys


def configure_git(prefix):
    """Configure git so GitHub (and related hosts) work through the IITD HTTP proxy."""
    if not shutil.which("git"):
        log("Git: not installed, skipping.")
        return "SKIPPED"

    url = proxy_url(prefix)
    system_git = ["git", "config", "--system"]
    failed = False

    for key in _git_proxy_keys():
        result = run_cmd(system_git + ["--replace-all", key, url], check=False, timeout=15)
        if result.returncode != 0:
            failed = True

    # Force HTTPS for GitHub so traffic can use the HTTP CONNECT proxy
    # (git:// and SSH often fail or are blocked on campus).
    run_cmd(system_git + ["--unset-all", "url.https://github.com/.insteadOf"], check=False, timeout=10)
    for instead in ("git://github.com/", "git@github.com:"):
        result = run_cmd(
            system_git + ["--add", "url.https://github.com/.insteadOf", instead],
            check=False,
            timeout=15,
        )
        if result.returncode != 0:
            failed = True

    user_info = target_user_record()
    if user_info:
        user_git = ["sudo", "-u", user_info.pw_name, "git", "config", "--global"]
        for key in _git_proxy_keys():
            run_cmd(user_git + ["--replace-all", key, url], check=False, timeout=15)
        run_cmd(user_git + ["--unset-all", "url.https://github.com/.insteadOf"], check=False, timeout=10)
        for instead in ("git://github.com/", "git@github.com:"):
            run_cmd(
                user_git + ["--add", "url.https://github.com/.insteadOf", instead],
                check=False,
                timeout=15,
            )

    if shutil.which("gh"):
        log("GitHub CLI (gh): uses http(s)_proxy from environment / profile.")

    if failed:
        log("Git/GitHub proxy could not be fully configured.")
        return "CHECK"

    log("Git/GitHub proxy configured (system-wide + GitHub hosts).")
    return "OK"


def remove_git_proxy():
    if not shutil.which("git"):
        return "SKIPPED"

    keys = _git_proxy_keys() + ["url.https://github.com/.insteadOf"]
    system_git = ["git", "config", "--system"]
    for key in keys:
        run_cmd(system_git + ["--unset-all", key], check=False, timeout=15)

    user_info = target_user_record()
    if user_info:
        user_git = ["sudo", "-u", user_info.pw_name, "git", "config", "--global"]
        for key in keys:
            run_cmd(user_git + ["--unset-all", key], check=False, timeout=15)

    log("Git/GitHub proxy removed.")
    return "OK"


def desktop_user_env(user_info, extra=None):
    runtime_dir = "/run/user/{0}".format(user_info.pw_uid)
    env = {
        "DISPLAY": os.environ.get("DISPLAY", ":0"),
        "DBUS_SESSION_BUS_ADDRESS": "unix:path={0}/bus".format(runtime_dir),
        "XDG_RUNTIME_DIR": runtime_dir,
    }
    if extra:
        env.update(extra)
    return env


def gsettings_base(user_info, env):
    return [
        "sudo",
        "-u",
        user_info.pw_name,
        "env",
        "DISPLAY={0}".format(env["DISPLAY"]),
        "DBUS_SESSION_BUS_ADDRESS={0}".format(env["DBUS_SESSION_BUS_ADDRESS"]),
        "XDG_RUNTIME_DIR={0}".format(env["XDG_RUNTIME_DIR"]),
    ]


def configure_gsettings(prefix):
    if not shutil.which("gsettings"):
        log("gsettings: not installed, skipping desktop proxy.")
        return "SKIPPED"

    user_info = target_user_record()
    if not user_info:
        log("gsettings: no desktop user detected (use sudo from a logged-in user).")
        return "SKIPPED"

    runtime_dir = "/run/user/{0}".format(user_info.pw_uid)
    if not path_exists(path_join(runtime_dir, "bus")):
        log("gsettings: desktop DBus session not found, skipping.")
        return "SKIPPED"

    host = proxy_host(prefix)
    env = desktop_user_env(user_info)
    base = gsettings_base(user_info, env)
    commands = [
        base + ["gsettings", "set", "org.gnome.system.proxy", "mode", "manual"],
        base + ["gsettings", "set", "org.gnome.system.proxy.http", "host", host],
        base + ["gsettings", "set", "org.gnome.system.proxy.http", "port", str(PROXY_PORT)],
        base + ["gsettings", "set", "org.gnome.system.proxy.https", "host", host],
        base + ["gsettings", "set", "org.gnome.system.proxy.https", "port", str(PROXY_PORT)],
        base + ["gsettings", "set", "org.gnome.system.proxy.ftp", "host", host],
        base + ["gsettings", "set", "org.gnome.system.proxy.ftp", "port", str(PROXY_PORT)],
        base + ["gsettings", "set", "org.gnome.system.proxy", "ignore-hosts", "['localhost', '127.0.0.1', '::1']"],
    ]

    failed = False
    for command in commands:
        result = run_cmd(command, check=False, timeout=10)
        if result.returncode != 0 or "failed to commit changes" in result.stdout.lower():
            failed = True

    if failed:
        log("Ubuntu desktop proxy could not be fully applied.")
        return "CHECK"

    log("Ubuntu GUI proxy enabled (GNOME).")
    return "OK"


def browser_policy_content(prefix):
    host = proxy_host(prefix)
    return {
        "ProxyMode": "fixed_servers",
        "ProxyServer": "http://{0}:{1}".format(host, PROXY_PORT),
        "ProxyBypassList": NO_PROXY,
    }


def firefox_policy_content(prefix):
    host = proxy_host(prefix)
    return {
        "policies": {
            "Proxy": {
                "Mode": "manual",
                "HTTPProxy": host,
                "HTTPPort": PROXY_PORT,
                "SSLProxy": host,
                "SSLPort": PROXY_PORT,
                "Passthrough": NO_PROXY,
            }
        }
    }


def configure_browser_policies(prefix):
    configured = False
    host = proxy_host(prefix)
    proxy_server = "http://{0}:{1}".format(host, PROXY_PORT)

    if path_exists("/opt/google/chrome") or shutil.which("google-chrome") or shutil.which("google-chrome-stable"):
        write_text_file(CHROME_POLICY_FILE, json.dumps(browser_policy_content(prefix), indent=2) + "\n")
        configured = True
        log("Google Chrome policy configured ({0}).".format(CHROME_POLICY_FILE))

    if path_exists("/usr/bin/chromium-browser") or path_exists("/usr/bin/chromium") or shutil.which("chromium"):
        write_text_file(CHROMIUM_POLICY_FILE, json.dumps(browser_policy_content(prefix), indent=2) + "\n")
        configured = True
        log("Chromium policy configured ({0}).".format(CHROMIUM_POLICY_FILE))

    if shutil.which("firefox") or path_exists("/usr/lib/firefox"):
        write_text_file(FIREFOX_POLICY_FILE, json.dumps(firefox_policy_content(prefix), indent=2) + "\n")
        configured = True
        log("Firefox policy configured ({0}).".format(FIREFOX_POLICY_FILE))

    if not configured:
        log("No supported browsers found for policy configuration.")
        return "SKIPPED"

    log("Browser proxy target: {0}".format(proxy_server))
    return "OK"


def proxy_exec_line(prefix, original_exec):
    url = proxy_url(prefix).rstrip("/")
    env_parts = [
        "http_proxy={0}".format(url),
        "https_proxy={0}".format(url),
        "HTTP_PROXY={0}".format(url),
        "HTTPS_PROXY={0}".format(url),
        "no_proxy={0}".format(NO_PROXY),
        "NO_PROXY={0}".format(NO_PROXY),
    ]
    command = original_exec[len("Exec="):].strip()
    if "--proxy-server=" not in command:
        command = '{0} --proxy-server={1} "--proxy-bypass-list=localhost;127.0.0.1;::1"'.format(command, url)
    return "Exec=env " + " ".join(env_parts) + " " + command


def configure_browser_launchers(prefix, user_info):
    target_dir = path_join(user_info.pw_dir, ".local", "share", "applications")
    ensure_user_dir(target_dir, user_info)
    configured = False

    for source_path in BROWSER_DESKTOP_SOURCES:
        if not path_exists(source_path):
            continue

        lines = read_text_file(source_path).splitlines()
        updated = []
        for line in lines:
            if line.startswith("Exec=") and not line.startswith("Exec=env "):
                updated.append(proxy_exec_line(prefix, line))
            else:
                updated.append(line)

        target = path_join(target_dir, os.path.basename(source_path))
        write_text_file(target, "\n".join(updated).rstrip() + "\n")
        chown_to_user(target, user_info)
        log("Browser launcher proxy configured: {0}".format(target))
        configured = True

    if not configured:
        return "SKIPPED"

    if shutil.which("update-desktop-database"):
        run_cmd(
            ["sudo", "-u", user_info.pw_name, "update-desktop-database", target_dir],
            check=False,
            timeout=20,
        )
    return "OK"


def configure_user_tools(prefix):
    user_info = target_user_record()
    if not user_info:
        log("User tools: no sudo desktop user detected, skipping per-user config.")
        return "SKIPPED"

    url = proxy_url(prefix)
    home = user_info.pw_dir

    env_dir = path_join(home, ".config", "environment.d")
    env_file = path_join(env_dir, "95-iitd-proxy.conf")
    env_content = "\n".join(
        [
            "http_proxy={0}".format(url),
            "https_proxy={0}".format(url),
            "ftp_proxy={0}".format(url),
            "HTTP_PROXY={0}".format(url),
            "HTTPS_PROXY={0}".format(url),
            "FTP_PROXY={0}".format(url),
            "no_proxy={0}".format(NO_PROXY),
            "NO_PROXY={0}".format(NO_PROXY),
        ]
    )
    mkdir_p(env_dir)
    write_text_file(env_file, env_content + "\n")
    chown_to_user(env_dir, user_info)
    chown_to_user(env_file, user_info)
    log("User session proxy configured: {0}".format(env_file))

    wgetrc = path_join(home, ".wgetrc")
    replace_managed_block(
        wgetrc,
        "\n".join(
            [
                "use_proxy = on",
                "http_proxy = {0}".format(url),
                "https_proxy = {0}".format(url),
                "ftp_proxy = {0}".format(url),
                "no_proxy = {0}".format(NO_PROXY),
            ]
        ),
    )
    chown_to_user(wgetrc, user_info)
    log("wget proxy configured: {0}".format(wgetrc))

    curlrc = path_join(home, ".curlrc")
    replace_managed_block(
        curlrc,
        "\n".join(['proxy = "{0}"'.format(url), 'noproxy = "{0}"'.format(NO_PROXY)]),
    )
    chown_to_user(curlrc, user_info)
    log("curl proxy configured: {0}".format(curlrc))

    runtime_dir = "/run/user/{0}".format(user_info.pw_uid)
    if path_exists(path_join(runtime_dir, "bus")):
        runtime_env = proxy_env(prefix)
        runtime_env.update(desktop_user_env(user_info))
        keys = [
            "http_proxy", "https_proxy", "ftp_proxy",
            "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY",
            "no_proxy", "NO_PROXY",
        ]
        user_env_command = [
            "sudo", "-u", user_info.pw_name, "env",
            "DISPLAY={0}".format(runtime_env["DISPLAY"]),
            "DBUS_SESSION_BUS_ADDRESS={0}".format(runtime_env["DBUS_SESSION_BUS_ADDRESS"]),
            "XDG_RUNTIME_DIR={0}".format(runtime_env["XDG_RUNTIME_DIR"]),
        ] + ["{0}={1}".format(key, runtime_env[key]) for key in keys]

        run_cmd(user_env_command + ["systemctl", "--user", "import-environment"] + keys, check=False, timeout=15)
        if shutil.which("dbus-update-activation-environment"):
            run_cmd(
                user_env_command + ["dbus-update-activation-environment", "--systemd"] + keys,
                check=False,
                timeout=15,
            )
    else:
        log("User runtime session not found; reopen apps after proxy setup.")

    launcher_status = configure_browser_launchers(prefix, user_info)
    log("Restart open browsers/apps to pick up proxy changes.")
    return "OK" if launcher_status in ("OK", "SKIPPED") else "CHECK"


def save_state(role, userid, prefix):
    mkdir_p(STATE_DIR)
    state = {
        "role": role,
        "userid": userid,
        "proxy_host": proxy_host(prefix),
        "proxy_port": PROXY_PORT,
        "python_version": "{0}.{1}".format(sys.version_info[0], sys.version_info[1]),
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    write_text_file(STATE_FILE, json.dumps(state, indent=2, sort_keys=True) + "\n")


def remove_path(path):
    try:
        if path_exists(path):
            os.remove(path)
            log("Removed {0}".format(path))
    except (OSError, IOError) as exc:
        log("Could not remove {0}: {1}".format(path, exc))


def remove_environment_entries():
    managed_keys = {
        "http_proxy", "https_proxy", "ftp_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY",
        "no_proxy", "NO_PROXY",
    }
    if not path_exists(ENV_FILE):
        return
    kept = []
    for line in read_text_file(ENV_FILE).splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key not in managed_keys:
            kept.append(line)
    write_text_file(ENV_FILE, "\n".join(kept).rstrip() + ("\n" if kept else ""))
    log("Cleaned proxy entries from {0}".format(ENV_FILE))


def remove_snap_proxy():
    if not shutil.which("snap"):
        return "SKIPPED"
    run_cmd(["snap", "unset", "system", "proxy.http", "proxy.https"], check=False, timeout=30)
    return "OK"


def remove_gsettings_proxy():
    if not shutil.which("gsettings"):
        return "SKIPPED"

    user_info = target_user_record()
    if not user_info:
        return "SKIPPED"

    env = desktop_user_env(user_info)
    base = gsettings_base(user_info, env)
    commands = [
        base + ["gsettings", "set", "org.gnome.system.proxy", "mode", "none"],
        base + ["gsettings", "set", "org.gnome.system.proxy.http", "host", ""],
        base + ["gsettings", "set", "org.gnome.system.proxy.http", "port", "0"],
        base + ["gsettings", "set", "org.gnome.system.proxy.https", "host", ""],
        base + ["gsettings", "set", "org.gnome.system.proxy.https", "port", "0"],
        base + ["gsettings", "set", "org.gnome.system.proxy.ftp", "host", ""],
        base + ["gsettings", "set", "org.gnome.system.proxy.ftp", "port", "0"],
    ]
    failed = any(run_cmd(command, check=False, timeout=10).returncode != 0 for command in commands)
    if failed:
        log("Ubuntu desktop proxy could not be fully disabled.")
        return "CHECK"
    log("Ubuntu GUI proxy disabled.")
    return "OK"


def remove_browser_policies():
    removed = False
    for path in (CHROME_POLICY_FILE, CHROMIUM_POLICY_FILE, FIREFOX_POLICY_FILE):
        if path_exists(path):
            remove_path(path)
            removed = True
    return "OK" if removed else "SKIPPED"


def clear_user_runtime_proxy(user_info):
    runtime_dir = "/run/user/{0}".format(user_info.pw_uid)
    if not path_exists(path_join(runtime_dir, "bus")):
        return
    keys = [
        "http_proxy", "https_proxy", "ftp_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY",
        "no_proxy", "NO_PROXY",
    ]
    run_cmd(
        ["sudo", "-u", user_info.pw_name, "systemctl", "--user", "unset-environment"] + keys,
        check=False,
        timeout=15,
    )


def remove_user_tools():
    user_info = target_user_record()
    if not user_info:
        return "SKIPPED"

    home = user_info.pw_dir
    remove_path(path_join(home, ".config", "environment.d", "95-iitd-proxy.conf"))
    remove_managed_block(path_join(home, ".wgetrc"))
    remove_managed_block(path_join(home, ".curlrc"))
    clear_user_runtime_proxy(user_info)

    launcher_dir = path_join(home, ".local", "share", "applications")
    for source_path in BROWSER_DESKTOP_SOURCES:
        remove_path(path_join(launcher_dir, os.path.basename(source_path)))

    return "OK"


def enable_proxy(role, userid, password):
    require_root()
    prefix = PREFIX_MAP[role]

    remove_legacy_iitd_ca_files()

    log("Python runtime: {0}.{1}".format(sys.version_info[0], sys.version_info[1]))
    log("IITD role: {0}".format(role))
    log("IITD userid: {0}".format(userid))
    log("Proxy endpoint: {0}".format(proxy_url(prefix)))

    log("Logging in to IITD proxy...")
    login(role, prefix, userid, password)

    configure_apt(prefix)
    configure_environment(prefix)
    configure_systemd(prefix)

    snap_status = configure_snap(prefix)
    git_status = configure_git(prefix)
    gnome_status = configure_gsettings(prefix)
    browser_status = configure_browser_policies(prefix)
    user_status = configure_user_tools(prefix)

    save_state(role, userid, prefix)

    log("")
    log("Proxy setup summary")
    log("-------------------")
    log("APT:       OK")
    log("Snap:      {0}".format(snap_status))
    log("GitHub:    {0}".format(git_status))
    log("GUI:       {0}".format(gnome_status))
    log("Browsers:  {0}".format(browser_status))
    log("wget/curl: {0}".format(user_status))
    log("")
    log("Proxy enabled system-wide. Restart browsers if they were already open.")


def logout_proxy():
    require_root()

    remove_path(APT_PROXY_FILE)
    remove_path(PROFILE_FILE)
    remove_path(SYSTEMD_PROXY_FILE)
    remove_path(SYSTEMD_USER_PROXY_FILE)
    remove_environment_entries()

    snap_status = remove_snap_proxy()
    git_status = remove_git_proxy()
    gnome_status = remove_gsettings_proxy()
    browser_status = remove_browser_policies()
    user_status = remove_user_tools()

    if shutil.which("systemctl"):
        run_cmd(["systemctl", "daemon-reexec"], check=False, timeout=15)

    if path_exists(STATE_FILE):
        remove_path(STATE_FILE)

    log("")
    log("Proxy logout summary")
    log("--------------------")
    log("Snap:      {0}".format(snap_status))
    log("GitHub:    {0}".format(git_status))
    log("GUI:       {0}".format(gnome_status))
    log("Browsers:  {0}".format(browser_status))
    log("User tools:{0}".format(user_status))
    log("")
    log("Proxy removed from system.")


def interactive_shell():
    require_root()

    print("")
    print("=== IITD Proxy Shell ===")
    print("Login to enable IITD proxy on this system.")
    print("Roles: {0}".format(", ".join(sorted(PREFIX_MAP))))
    print("Type 'exit' at Role/Userid prompt to quit without login.")
    print("")

    while True:
        role = prompt_input("Role: ").lower()
        if role in ("exit", "quit", "q"):
            log("Proxy shell closed without login.")
            return 2

        if role not in PREFIX_MAP:
            print("Invalid role. Choose from: {0}".format(", ".join(sorted(PREFIX_MAP))))
            continue

        userid = prompt_input("Userid: ")
        if userid.lower() in ("exit", "quit", "q"):
            log("Proxy shell closed without login.")
            return 2

        password = getpass.getpass("IITD proxy password: ")
        try:
            enable_proxy(role, userid, password)
            return 0
        except ProxyError as exc:
            print("ERROR: {0}".format(exc))
            print("Try again, or type 'exit' at the Role prompt.")
            print("")


def prompt_input(label):
    if PY3:
        return input(label).strip()
    return raw_input(label).strip()  # noqa: F821 — raw_input exists in Python 2


def normalize_argv(argv):
    if len(argv) < 2:
        return argv

    command = argv[1].lower()
    if command in ("logout", "remove", "disable", "off"):
        return [argv[0], "logout"]
    if command in ("help", "-h", "--help"):
        return [argv[0], "help"]
    if command in ("shell", "interactive"):
        return [argv[0], "shell"]
    if command in PREFIX_MAP:
        userid = argv[2] if len(argv) > 2 else ""
        return [argv[0], "enable", argv[1], userid]
    if command in ("enable", "install", "setup") and len(argv) >= 4:
        return [argv[0], "enable", argv[2], argv[3]]
    return argv


def build_parser():
    roles = ", ".join(sorted(PREFIX_MAP))
    parser = argparse.ArgumentParser(
        prog="iitd-proxy",
        description="Enable or disable IITD proxy across Ubuntu (apt, snap, GUI, browsers, wget, curl).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  iitd-proxy staff krajaymeena\n"
            "  iitd-proxy phd ankit\n"
            "  iitd-proxy btech USERID\n"
            "  iitd-proxy logout\n"
            "  iitd-proxy shell\n\n"
            "After Proxy Setup install, any user can run these without typing sudo.\n"
            "Roles: {0}\n\n"
            "Works with Python 2.7 and Python 3.x."
        ).format(roles),
    )
    subparsers = parser.add_subparsers(dest="command")

    try:
        subparsers.required = True
    except Exception:
        pass

    enable = subparsers.add_parser("enable", aliases=("install", "setup"), help="login and enable proxy")
    enable.add_argument("role", choices=sorted(PREFIX_MAP))
    enable.add_argument("userid")
    enable.add_argument("password", nargs="?", help="prompted securely if omitted")

    subparsers.add_parser("logout", aliases=("remove", "disable"), help="remove proxy from entire system")
    subparsers.add_parser("shell", aliases=("interactive",), help="interactive proxy login shell (type exit to quit)")
    return parser


def print_help():
    build_parser().print_help()


def main():
    argv = normalize_argv(sys.argv)

    if len(argv) >= 2 and argv[1] == "help":
        print_help()
        return 0

    parser = build_parser()
    args = parser.parse_args(argv[1:])

    try:
        if args.command in ("enable", "install", "setup"):
            if not args.password:
                args.password = getpass.getpass("IITD proxy password: ")
            enable_proxy(args.role, args.userid, args.password)
        elif args.command in ("logout", "remove", "disable"):
            logout_proxy()
        elif args.command in ("shell", "interactive"):
            return interactive_shell()
        else:
            parser.error("Unknown command")
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130
    except ProxyError as exc:
        log("ERROR: {0}".format(exc))
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
