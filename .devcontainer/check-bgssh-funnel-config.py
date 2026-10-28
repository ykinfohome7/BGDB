#!/usr/bin/env python3
"""Read Tailscale Serve/Funnel status --json and classify HTTPS listeners.

No network, no mutation, no authentication values. Prints one JSON object:
{"443":"match|occupied|free", "8443":"...", "10000":"..."}.
"""
import json
import sys

PORTS = ("443", "8443", "10000")
PROXIES = {"http://127.0.0.1:8765", "http://localhost:8765"}


def classify(config):
    tcp = config.get("TCP") or {}
    web = config.get("Web") or {}
    allow = config.get("AllowFunnel") or {}
    result = {}
    for port in PORTS:
        web_entries = [
            (host_port, entry)
            for host_port, entry in web.items()
            if isinstance(host_port, str)
            and host_port.endswith(":" + port)
            and isinstance(entry, dict)
        ]
        listener = tcp.get(port)
        any_configured = listener is not None or bool(web_entries)
        if not any_configured:
            result[port] = "free"
            continue
        tcp_https = isinstance(listener, dict) and listener.get("HTTPS") is True
        matches = [
            host_port for host_port, entry in web_entries
            if (entry.get("Handlers") or {}).get("/", {}).get("Proxy") in PROXIES
            and allow.get(host_port) is True
        ]
        # Never claim a shared HTTPS listener is exclusively BGSSH unless
        # its single configured root matches and is explicitly a Funnel.
        result[port] = (
            "match" if tcp_https and len(web_entries) == 1
            and len(matches) == 1 and
            set((web_entries[0][1].get("Handlers") or {}).keys()) == {"/"}
            else "occupied"
        )
    return result


if __name__ == "__main__":
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError("Expected a Tailscale ServeConfig JSON object")
    print(json.dumps(classify(data), separators=(",", ":")))
