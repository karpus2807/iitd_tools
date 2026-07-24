#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IITD Lab — ThingsBoard device telemetry client (Raspberry Pi 3 / 4)

Transports:
  http  — Device HTTP API via IITD HTTP proxy (campus-friendly, DEFAULT)
  mqtt  — Direct MQTT :1883 (only if port is open; HTTP proxy cannot carry MQTT)

Config: /etc/iitd-thingsboard.conf
"""

from __future__ import print_function

import json
import logging
import os
import pathlib
import ssl
import subprocess
import time
import urllib.error
import urllib.request

CONFIG_FILE = os.environ.get("IITD_TB_CONFIG", "/etc/iitd-thingsboard.conf")

DEFAULT_HOST = "thingsboard.ipserver.in"
DEFAULT_PORT = 1883
DEFAULT_INTERVAL = 30
DEFAULT_TRANSPORT = "http"  # campus: use proxy-friendly HTTP API

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("iitd-thingsboard")

client = None
period = 1.0
interval_sec = DEFAULT_INTERVAL


def load_config(path=CONFIG_FILE):
    cfg = {
        "TB_HOST": os.environ.get("TB_HOST", DEFAULT_HOST),
        "TB_PORT": os.environ.get("TB_PORT", str(DEFAULT_PORT)),
        "TB_ACCESS_TOKEN": os.environ.get("TB_ACCESS_TOKEN", ""),
        "TB_INTERVAL": os.environ.get("TB_INTERVAL", str(DEFAULT_INTERVAL)),
        "TB_DEVICE_NAME": os.environ.get("TB_DEVICE_NAME", ""),
        "TB_TRANSPORT": os.environ.get("TB_TRANSPORT", DEFAULT_TRANSPORT),
        # Full HTTP API base, e.g. https://thingsboard.ipserver.in
        # or http://thingsboard.ipserver.in:8080
        "TB_HTTP_BASE": os.environ.get("TB_HTTP_BASE", ""),
        # Campus MITM / proxy certs — default off verify for lab nets
        "TB_SSL_VERIFY": os.environ.get("TB_SSL_VERIFY", "0"),
        "TB_HTTP_PROXY": os.environ.get("TB_HTTP_PROXY", ""),
        "TB_HTTPS_PROXY": os.environ.get("TB_HTTPS_PROXY", ""),
    }
    if os.path.isfile(path):
        with open(path, "r") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip("'").strip('"')
                if key in cfg or key.startswith("TB_"):
                    cfg[key] = value
    return cfg


def run(cmd):
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=15
        )
        return (result.stdout or "").strip().replace(",", ".")
    except Exception as exc:
        log.warning("command failed: %s (%s)", cmd, exc)
        return ""


def safe_float(value, default=0.0):
    try:
        if value is None or value == "":
            return default
        text = str(value).lower()
        if text in ("nan", "inf", "-inf"):
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def pick_primary_iface():
    net = pathlib.Path("/sys/class/net")
    preferred = ("eth0", "wlan0", "enp0s3", "ens3")
    for name in preferred:
        path = net / name / "address"
        if path.is_file():
            return name, path.read_text().strip()
    for path in sorted(net.glob("*/address")):
        iface = path.parent.name
        if iface == "lo":
            continue
        mac = path.read_text().strip()
        if mac and mac != "00:00:00:00:00:00":
            return iface, mac
    return "unknown", "00:00:00:00:00:00"


def get_data():
    cpu_raw = run(
        "grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}'"
    )
    cpu_usage = round(safe_float(cpu_raw), 2)

    ip_line = run("hostname -I")
    ip_address = ip_line.split()[0] if ip_line else "0.0.0.0"
    iface, mac_address = pick_primary_iface()

    processes_count = int(
        safe_float(run("ps -Al 2>/dev/null | grep -c bash || true"), 0)
    )
    swap_memory_usage = round(
        safe_float(
            run(
                "free -m | awk '/Swap/ { if ($2+0==0) print 0; else print ($3/$2)*100 }'"
            )
        ),
        2,
    )
    ram_usage = round(
        safe_float(
            run(
                "free -m | awk '/Mem/ { if ($2+0==0) print 0; else print ($3/$2)*100 }'"
            )
        ),
        2,
    )

    try:
        st = os.statvfs("/")
        disk_usage = (
            round((st.f_blocks - st.f_bfree) / float(st.f_blocks) * 100, 2)
            if st.f_blocks > 0
            else 0.0
        )
    except OSError:
        disk_usage = 0.0

    boot_time = run("uptime -p") or run("uptime")
    avg_load = round((cpu_usage + ram_usage) / 2.0, 2)

    model = ""
    model_path = pathlib.Path("/proc/device-tree/model")
    if model_path.is_file():
        try:
            model = model_path.read_text().replace("\x00", "").strip()
        except OSError:
            model = ""

    attributes = {
        "ip_address": ip_address,
        "macaddress": mac_address,
        "iface": iface,
    }
    if model:
        attributes["board_model"] = model

    telemetry = {
        "cpu_usage": cpu_usage,
        "processes_count": processes_count,
        "disk_usage": disk_usage,
        "RAM_usage": ram_usage,
        "swap_memory_usage": swap_memory_usage,
        "boot_time": boot_time,
        "avg_load": avg_load,
    }
    return attributes, telemetry


def resolve_proxy_url(cfg):
    """Pick IITD HTTP proxy from config or environment."""
    for key in ("TB_HTTPS_PROXY", "TB_HTTP_PROXY", "https_proxy", "http_proxy", "HTTPS_PROXY", "HTTP_PROXY"):
        if key.startswith("TB_"):
            val = (cfg.get(key) or "").strip()
        else:
            val = (os.environ.get(key) or "").strip().strip('"')
        if val:
            return val
    return ""


def http_post_json(url, payload, proxy_url, verify_ssl):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    handlers = []
    if proxy_url:
        handlers.append(
            urllib.request.ProxyHandler(
                {"http": proxy_url, "https": proxy_url}
            )
        )
    else:
        handlers.append(urllib.request.ProxyHandler({}))

    if not verify_ssl:
        ctx = ssl._create_unverified_context()
        handlers.append(urllib.request.HTTPSHandler(context=ctx))

    opener = urllib.request.build_opener(*handlers)
    with opener.open(req, timeout=25) as resp:
        body = resp.read()
        return resp.getcode(), body.decode("utf-8", "replace")


def http_send(cfg, attributes, telemetry):
    token = cfg["TB_ACCESS_TOKEN"].strip()
    base = (cfg.get("TB_HTTP_BASE") or "").strip().rstrip("/")
    if not base:
        host = cfg.get("TB_HOST") or DEFAULT_HOST
        base = "https://{0}".format(host)

    proxy_url = resolve_proxy_url(cfg)
    verify = str(cfg.get("TB_SSL_VERIFY", "0")).lower() in ("1", "true", "yes")

    # Try primary base, then common ThingsBoard HTTP port
    bases = [base]
    alt = "http://{0}:8080".format(cfg.get("TB_HOST") or DEFAULT_HOST)
    if alt not in bases:
        bases.append(alt)

    last_err = None
    for b in bases:
        tel_url = "{0}/api/v1/{1}/telemetry".format(b, token)
        attr_url = "{0}/api/v1/{1}/attributes".format(b, token)
        try:
            code1, _ = http_post_json(tel_url, telemetry, proxy_url, verify)
            code2, _ = http_post_json(attr_url, attributes, proxy_url, verify)
            if code1 in (200, 201) and code2 in (200, 201):
                log.info(
                    "HTTP OK via %s (proxy=%s) telemetry=%s attributes=%s",
                    b,
                    "yes" if proxy_url else "no",
                    code1,
                    code2,
                )
                return True
            last_err = "HTTP {0}/{1} from {2}".format(code1, code2, b)
            log.warning(last_err)
        except Exception as exc:
            last_err = "{0} ({1})".format(exc, b)
            log.warning("HTTP send failed: %s", last_err)
    raise RuntimeError(last_err or "HTTP send failed")


def run_http_loop(cfg):
    proxy_url = resolve_proxy_url(cfg)
    log.info(
        "Transport=HTTP (uses IITD proxy). proxy=%s ssl_verify=%s",
        proxy_url or "(none)",
        cfg.get("TB_SSL_VERIFY", "0"),
    )
    while True:
        try:
            attributes, telemetry = get_data()
            http_send(cfg, attributes, telemetry)
        except Exception as exc:
            log.error("HTTP telemetry failed: %s", exc)
            log.warning("Retrying in 30s...")
            time.sleep(30)
            continue
        time.sleep(interval_sec)


def connect_mqtt_client(host, port, token):
    global client
    from tb_gateway_mqtt import TBDeviceMqttClient

    try:
        client = TBDeviceMqttClient(host, port=port, username=token)
    except TypeError:
        client = TBDeviceMqttClient(host, username=token)
    client.connect()
    return client


def run_mqtt_loop(cfg):
    global client
    host = cfg.get("TB_HOST") or DEFAULT_HOST
    port = int(safe_float(cfg.get("TB_PORT"), DEFAULT_PORT))
    token = cfg["TB_ACCESS_TOKEN"].strip()

    log.warning(
        "Transport=MQTT — HTTP campus proxy cannot tunnel MQTT. "
        "Needs direct TCP to %s:%s (often blocked on IITD).",
        host,
        port,
    )

    while True:
        try:
            log.info("MQTT connecting to %s:%s ...", host, port)
            connect_mqtt_client(host, port, token)
            log.info("MQTT connected.")
            while client is not None and not getattr(client, "stopped", False):
                try:
                    attributes, telemetry = get_data()
                    client.send_attributes(attributes)
                    client.send_telemetry(telemetry)
                except Exception as exc:
                    log.error("MQTT send failed: %s", exc)
                    break
                time.sleep(interval_sec)
        except Exception as exc:
            log.error("MQTT session failed: %s", exc)
            log.warning("Retrying MQTT in 30s...")
        try:
            if client is not None:
                try:
                    client.disconnect()
                except Exception:
                    pass
        finally:
            client = None
        time.sleep(30)


def main():
    global interval_sec

    cfg = load_config()
    token = (cfg.get("TB_ACCESS_TOKEN") or "").strip()
    interval_sec = max(10, int(safe_float(cfg.get("TB_INTERVAL"), DEFAULT_INTERVAL)))
    transport = (cfg.get("TB_TRANSPORT") or DEFAULT_TRANSPORT).strip().lower()

    if not token:
        log.error("TB_ACCESS_TOKEN missing. Set in %s", CONFIG_FILE)
        raise SystemExit(1)

    log.info(
        "ThingsBoard client start transport=%s interval=%ss host=%s",
        transport,
        interval_sec,
        cfg.get("TB_HOST"),
    )

    if transport in ("http", "https", "api"):
        run_http_loop(cfg)
    else:
        run_mqtt_loop(cfg)


if __name__ == "__main__":
    main()
