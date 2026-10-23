#!/usr/bin/env python3
"""TLS 1.3 post-quantum key-exchange probe for owned BGDB domains.

Only a successfully negotiated TLS 1.3 group is evidence of PQ TLS support.
This is NOT QKD (photonic cryptography), NIST certification, or a Qualys grade.
"""
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

OWNED_HOSTS = ("bgspiritllc.com", "bgdb.eu")
GROUPS = (
    "X25519MLKEM768",
    "SecP256r1MLKEM768",
    "SecP384r1MLKEM1024",
    "MLKEM768",
    "MLKEM1024",
)
BASELINE_GROUP = "X25519"
OUTPUT = Path("reports/post-quantum-tls")
GROUP_PATTERN = re.compile(r"(?:Negotiated TLS1\.3 group|Server Temp Key)\s*:\s*([^\r\n]+)", re.I)
VERSION_PATTERN = re.compile(r"Protocol version\s*:\s*(TLSv1\.3)", re.I)


def scan_group(host: str, group: str) -> dict:
    command = [
        "openssl", "s_client", "-connect", f"{host}:443",
        "-servername", host, "-tls1_3", "-groups", group,
        "-brief", "-verify_return_error", "-verify_hostname", host,
    ]
    try:
        completed = subprocess.run(
            command, input=b"", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=18, check=False,
        )
    except subprocess.TimeoutExpired:
        return {"group_offered": group, "result": "inconclusive", "reason": "timeout"}
    except OSError as exc:
        return {"group_offered": group, "result": "inconclusive", "reason": str(exc)[:180]}

    combined = (completed.stdout + b"\n" + completed.stderr).decode("utf-8", errors="replace")
    version = VERSION_PATTERN.search(combined)
    negotiated = GROUP_PATTERN.search(combined)
    selected = negotiated.group(1).strip().split(",")[0].strip() if negotiated else None
    valid = completed.returncode == 0 and version is not None
    matched = valid and selected is not None and selected.lower() == group.lower()
    if matched:
        status = "negotiated"
    elif valid:
        status = "inconclusive" if selected is None else "not_negotiated"
    elif completed.returncode != 0:
        status = "not_negotiated"
    else:
        status = "inconclusive"
    return {
        "group_offered": group,
        "negotiated_group": selected,
        "tls_version": version.group(1) if version else None,
        "result": status,
        "exit_code": completed.returncode,
        "diagnostic": combined[-500:].strip(),
    }


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    openssl = subprocess.run(["openssl", "version"], capture_output=True, text=True, check=True).stdout.strip()
    version_match = re.search(r"OpenSSL\s+(\d+)\.(\d+)", openssl)
    if not version_match or tuple(map(int, version_match.groups())) < (3, 5):
        raise SystemExit(f"OpenSSL >= 3.5 required for native ML-KEM testing; found {openssl}")
    reports = []
    for host in OWNED_HOSTS:
        print(f"Checking owned domain: {host}", flush=True)
        baseline = scan_group(host, BASELINE_GROUP)
        checks = [scan_group(host, group) for group in GROUPS]
        confirmed = [item["group_offered"] for item in checks if item["result"] == "negotiated"]
        if confirmed:
            classification = "pq_kex_confirmed"
        elif baseline["result"] == "negotiated":
            classification = "pq_kex_not_confirmed"
        else:
            classification = "inconclusive"
        report = {
            "host": host,
            "checked_at_utc": datetime.now(timezone.utc).isoformat(),
            "engine": openssl,
            "tls_version_tested": "TLSv1.3",
            "status": classification,
            "negotiated_pq_groups": confirmed,
            "classical_baseline": baseline,
            "post_quantum_group_checks": checks,
            "scope": "Public HTTPS listener for this hostname; results may vary by CDN edge.",
            "interpretation": (
                "Evidence is an actual TLS 1.3 key exchange negotiated for a named ML-KEM group. "
                "A negative handshake does not certify absence of PQ support at all endpoints. "
                "No photonic/QKD assessment, signature-algorithm audit, independent certification, "
                "or A+/letter grade is provided."
            ),
        }
        (OUTPUT / f"{host}.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        reports.append(report)
        print(f"{host}: {classification}; negotiated PQ groups: {confirmed}", flush=True)
    (OUTPUT / "summary.json").write_text(json.dumps(reports, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
