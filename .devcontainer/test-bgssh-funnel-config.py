#!/usr/bin/env python3
"""Offline safety tests for BGSSH's Tailscale Funnel listener classifier."""
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("bgssh_funnel_config", root / "check-bgssh-funnel-config.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def status(port="443", proxy="http://127.0.0.1:8765", allowed=True):
    host = f"bgdb.example.ts.net:{port}"
    return {"TCP": {port: {"HTTPS": True}},
            "Web": {host: {"Handlers": {"/": {"Proxy": proxy}}}},
            "AllowFunnel": {host: allowed}}


def test():
    assert mod.classify({}) == {"443": "free", "8443": "free", "10000": "free"}
    own = mod.classify(status())
    assert own["443"] == "match" and own["8443"] == "free", own
    existing = mod.classify(status(proxy="http://127.0.0.1:3000"))
    assert existing["443"] == "occupied" and existing["8443"] == "free", existing
    private = mod.classify(status(allowed=False))
    assert private["443"] == "occupied", private
    fallback = mod.classify(status(port="8443"))
    assert fallback["8443"] == "match" and fallback["443"] == "free", fallback
    shared = status()
    shared["Web"]["bgdb.example.ts.net:443"]["Handlers"]["/other"] = {"Proxy": "http://127.0.0.1:4444"}
    assert mod.classify(shared)["443"] == "occupied"
    mixed = status()
    second = status(port="8443", proxy="http://127.0.0.1:3000")
    for k in ("TCP", "Web", "AllowFunnel"):
        mixed[k].update(second[k])
    result = mod.classify(mixed)
    assert result["443"] == "match" and result["8443"] == "occupied", result
    print("BGSSH Tailscale Funnel listener classification PASS (no live changes)")


if __name__ == "__main__":
    test()
