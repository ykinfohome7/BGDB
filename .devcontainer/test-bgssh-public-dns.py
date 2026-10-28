#!/usr/bin/env python3
"""Test public DNS result classification; all fixtures offline."""
import importlib.util
from pathlib import Path

path = Path(__file__).with_name("check-bgssh-public-dns.py")
spec = importlib.util.spec_from_file_location("bgssh_public_dns", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main():
    good = {"Status": 0, "Answer": [{"name": "x.ts.net.", "type": 1, "data": "203.0.113.1"}]}
    empty = {"Status": 0, "Answer": []}
    missing = {"Status": 3}
    assert module.classify([("A", good), ("AAAA", empty)]) == "PUBLIC_DNS_AVAILABLE"
    assert module.classify([("A", empty), ("AAAA", missing)]) == "PUBLIC_DNS_MISSING"
    assert module.classify([], 2) == "PUBLIC_DNS_UNVERIFIED"
    assert module.classify([("A", empty)], 1) == "PUBLIC_DNS_UNVERIFIED"
    assert module.classify([("A", {"Status": 2}), ("AAAA", missing)]) == "PUBLIC_DNS_UNVERIFIED"
    print("BGSSH external DNS classification PASS (offline, no external requests)")


if __name__ == "__main__":
    main()
