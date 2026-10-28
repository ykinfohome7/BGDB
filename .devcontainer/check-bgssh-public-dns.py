#!/usr/bin/env python3
"""Check PUBLIC DNS for a Tailscale Funnel hostname (not tailnet MagicDNS).

Uses Google's DNS-over-HTTPS resolver, entirely separate from Tailscale's
MagicDNS. Never reads a token or includes MCP credentials in HTTP requests.
Exit: 0 = has public A/AAAA, 1 = public record missing, 2 = cannot verify.
"""
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def classify(replies, errors=0):
    for kind, response in replies:
        expected = {"A": 1, "AAAA": 28}[kind]
        if response.get("Status") == 0 and any(
            answer.get("type") == expected and answer.get("data")
            for answer in response.get("Answer", [])
        ):
            return "PUBLIC_DNS_AVAILABLE"
    if errors == 0 and len(replies) == 2 and all(
        result.get("Status") in (0, 3) for _, result in replies
    ):
        return "PUBLIC_DNS_MISSING"
    return "PUBLIC_DNS_UNVERIFIED"


def main():
    if len(sys.argv) != 2:
        print("usage: check-bgssh-public-dns.py HOSTNAME", file=sys.stderr)
        return 2
    hostname = sys.argv[1].rstrip(".")
    if not re.fullmatch(r"[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.ts\.net", hostname):
        print("PUBLIC_DNS_INVALID_HOSTNAME")
        return 2

    replies = []
    errors = 0
    for rrtype in ("A", "AAAA"):
        query = urllib.parse.urlencode({"name": hostname, "type": rrtype})
        url = "https://dns.google/resolve?" + query
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/dns-json"})
            with urllib.request.urlopen(req, timeout=8) as r:
                replies.append((rrtype, json.load(r)))
        except (OSError, ValueError, urllib.error.URLError):
            errors += 1

    state = classify(replies, errors)
    print(state)
    return {"PUBLIC_DNS_AVAILABLE": 0, "PUBLIC_DNS_MISSING": 1, "PUBLIC_DNS_UNVERIFIED": 2}[state]


if __name__ == "__main__":
    raise SystemExit(main())
