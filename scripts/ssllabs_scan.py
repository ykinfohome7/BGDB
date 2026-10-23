#!/usr/bin/env python3
"""Query SSL Labs API v4; preserve successful evidence; log send/receive/retries.

Active SSL Labs scans are permitted only for OWNED_HOSTS. Public examples use
cached results and are never newly scanned by this client.
"""
import json
import os
import socket
import ipaddress
import re
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

OWNED_HOSTS = ("bgspiritllc.com", "bgdb.eu")
EXAMPLE_HOSTS = ("google.com", "yahoo.com", "meta.com", "money.bg")
def safe_host(raw):
    host = raw.strip().lower().rstrip(".")
    if not host:
        return ""
    try:
        host = host.encode("idna").decode("ascii")
    except UnicodeError:
        raise SystemExit("Invalid internationalized hostname")
    if len(host) > 253 or not re.fullmatch(r"(?=.{1,253}$)[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host):
        raise SystemExit("Invalid hostname")
    if ".." in host or "." not in host:
        raise SystemExit("Fully-qualified public hostname required")
    return host


def selected_hosts():
    requested = safe_host(os.environ.get("TARGET_HOST", ""))
    if requested:
        return (requested,)
    extra = [safe_host(h) for h in os.environ.get("BGDB_EXTRA_HOSTS", "").split(",") if h.strip()]
    return tuple(dict.fromkeys((*OWNED_HOSTS, *EXAMPLE_HOSTS, *extra)))


ALL_HOSTS = selected_hosts()
API = "https://api.ssllabs.com/api/v4/analyze"
OUT = Path("reports/ssl-labs")
TRANSPORT = Path("reports/transport")
EMAIL = os.environ.get("SSL_LABS_EMAIL", "").strip()
EVENTS = []
SUMMARY = []


def now():
    return datetime.now(timezone.utc).isoformat()


def request(host, params, phase):
    """Record every network attempt, including HTTP errors and no-response cases."""
    q = urllib.parse.urlencode({"host": host, "all": "done", **params})
    url = API + "?" + q
    response = None
    for attempt in range(1, 4):
        rid = str(uuid.uuid4())
        start = time.monotonic()
        event = {
            "request_id": rid, "host": host, "phase": phase,
            "attempt": attempt, "sent_at_utc": now(), "method": "GET",
            "api": "SSL Labs v4 analyze", "parameters": params,
            "send": "sent", "receive": "not_yet", "http_status": None,
            "elapsed_ms": None, "error": None, "retry": False,
        }
        print(f"SEND {rid} host={host} phase={phase} attempt={attempt}", flush=True)
        try:
            req = urllib.request.Request(url, headers={
                "email": EMAIL, "Accept": "application/json",
                "User-Agent": "BGDB-SSL-TLS-Reporter/2.0"
            })
            with urllib.request.urlopen(req, timeout=45) as stream:
                event["http_status"] = stream.status
                response = json.load(stream)
                event["receive"] = "received"
                event["api_status"] = response.get("status")
        except urllib.error.HTTPError as exc:
            event["receive"] = "http_error_response_received"
            event["http_status"] = exc.code
            event["error"] = f"HTTP {exc.code}"
            # 429/5xx may recover; 4xx other than rate limits should not loop.
            if exc.code not in (429, 500, 502, 503, 504):
                event["elapsed_ms"] = int((time.monotonic() - start) * 1000)
                event["received_at_utc"] = now()
                EVENTS.append(event)
                print(f"RECEIVE {rid} HTTP {exc.code}", flush=True)
                return {"status": "HTTP_ERROR", "statusMessage": f"HTTP {exc.code}"}
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            # Timeout does NOT prove the remote API did not process the request.
            event["receive"] = "no_usable_response"
            event["error"] = type(exc).__name__ + ": " + str(exc)[:160]
        event["elapsed_ms"] = int((time.monotonic() - start) * 1000)
        event["received_at_utc"] = now()
        event["retry"] = event["receive"] != "received" and attempt < 3
        EVENTS.append(event)
        print(f"RECEIVE {rid} state={event['receive']} HTTP={event['http_status']} elapsed_ms={event['elapsed_ms']}", flush=True)
        if event["receive"] == "received":
            return response
        if attempt < 3:
            print(f"RETRY {rid} after {attempt * 3}s", flush=True)
            time.sleep(attempt * 3)
    return {"status": "NETWORK_ERROR", "statusMessage": "Three API attempts yielded no usable JSON; see transport trace"}



PREFLIGHT = Path("reports/preflight")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def verify_public_website(host):
    """Confirm that host resolves to public Internet addresses and HTTPS responds."""
    proof = {"host": host, "checked_at_utc": now(), "dns": "unchecked",
             "dns_addresses": [], "https": "unchecked", "http_status": None,
             "proceed_to_ssl_labs": False, "reason": None}
    try:
        infos = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        addresses = sorted({i[4][0] for i in infos})
        proof["dns_addresses"] = addresses
        if not addresses:
            proof["dns"] = "no_records"
            return proof
        if not all(ipaddress.ip_address(ip).is_global for ip in addresses):
            proof["dns"] = "blocked_non_public_address"
            proof["reason"] = "Security rule: scanner never scans hosts resolving to private or reserved IPs"
            return proof
        proof["dns"] = "public_addresses_found"
    except (socket.gaierror, OSError, ValueError) as exc:
        proof["dns"] = "resolution_failed"
        proof["reason"] = str(exc)[:160]
        return proof

    opener = urllib.request.build_opener(NoRedirect)
    for method in ("HEAD", "GET"):
        try:
            request_obj = urllib.request.Request(
                f"https://{host}/", method=method,
                headers={"User-Agent": "BGDB-Public-Website-Preflight/1.0"})
            with opener.open(request_obj, timeout=12) as response:
                proof["http_status"] = response.status
                proof["https"] = "responded"
                proof["proceed_to_ssl_labs"] = True
                break
        except urllib.error.HTTPError as exc:
            # Even 403/404/405/30x is a real HTTPS response from the host.
            proof["http_status"] = exc.code
            if exc.code == 405 and method == "HEAD":
                continue
            proof["https"] = "responded_with_http_status"
            proof["proceed_to_ssl_labs"] = True
            break
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            proof["reason"] = str(exc)[:160]
            if method == "GET":
                proof["https"] = "no_usable_https_response"
    return proof


def endpoint_summary(response):
    endpoints = []
    for ep in response.get("endpoints") or []:
        d = ep.get("details") or {}
        endpoints.append({
            "ipAddress": ep.get("ipAddress"), "grade": ep.get("grade"),
            "statusMessage": ep.get("statusMessage"),
            "protocols": d.get("protocols"), "namedGroups": d.get("namedGroups"),
            "forwardSecrecy": d.get("forwardSecrecy"),
        })
    return endpoints


def main():
    if not EMAIL:
        raise SystemExit("SSL_LABS_EMAIL must be set")
    OUT.mkdir(parents=True, exist_ok=True)
    TRANSPORT.mkdir(parents=True, exist_ok=True)
    PREFLIGHT.mkdir(parents=True, exist_ok=True)

    for host in ALL_HOSTS:
        path = OUT / (host + ".json")
        owned = host in OWNED_HOSTS
        proof = verify_public_website(host)
        (PREFLIGHT / (host + ".json")).write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"PREFLIGHT {host}: DNS={proof['dns']}, HTTPS={proof['https']}, status={proof['http_status']}", flush=True)
        if not proof["proceed_to_ssl_labs"]:
            SUMMARY.append({"host": host, "preflight": proof, "last_api_status": "NOT_STARTED",
                            "report_ready": False, "reason": "Preflight did not confirm a public HTTPS response"})
            (OUT / "multisite-summary.json").write_text(json.dumps(SUMMARY, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            continue
        fresh = request(host, {"fromCache": "on"}, "cached-lookup")
        mode = "cached-api"
        # Only owned sites can start a new assessment. External examples: cache ONLY.
        if owned and fresh.get("status") not in ("READY", "DNS", "IN_PROGRESS"):
            fresh = request(host, {"startNew": "on"}, "owned-scan-start")
            mode = "new-owned-scan"
        if owned and fresh.get("status") in ("DNS", "IN_PROGRESS"):
            for poll in range(36):
                time.sleep(12)
                fresh = request(host, {}, "owned-scan-poll")
                if fresh.get("status") in ("READY", "ERROR", "HTTP_ERROR", "NETWORK_ERROR"):
                    break

        # Do not replace previously verified JSON with a transient 429/timeout/error.
        is_ready = fresh.get("status") == "READY"
        reused_previous = False
        previous = None
        if not is_ready and path.exists():
            try:
                previous = json.loads(path.read_text(encoding="utf-8"))
            except (ValueError, OSError):
                pass
            if isinstance(previous, dict) and previous.get("status") == "READY":
                reused_previous = True
        if is_ready:
            path.write_text(json.dumps(fresh, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        elif reused_previous:
            mode = "previous-saved-report; current-request-not-ready"
        else:
            mode = "unavailable"
        evidence = fresh if is_ready else previous if reused_previous else {}
        SUMMARY.append({
            "host": host, "owned": owned, "preflight": proof, "source": "Qualys SSL Labs API v4",
            "requested_at_utc": now(), "last_api_status": fresh.get("status"),
            "last_api_message": fresh.get("statusMessage"),
            "report_mode": mode, "report_ready": is_ready or reused_previous,
            "newly_retrieved": is_ready,
            "previous_report_reused": reused_previous,
            "report_test_time_ms": evidence.get("testTime"),
            "endpoints": endpoint_summary(evidence),
            "transport_attempt_count": sum(e["host"] == host for e in EVENTS),
            "transport_retry_count": sum(e["host"] == host and e["retry"] for e in EVENTS),
            "transport_no_usable_response_count": sum(e["host"] == host and e["receive"] == "no_usable_response" for e in EVENTS),
            "trace": "reports/transport/ssl-labs-api.json",
        })
        print(f"RESULT {host}: current={fresh.get('status')} mode={mode}", flush=True)
        (TRANSPORT / "ssl-labs-api.json").write_text(json.dumps(EVENTS, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (OUT / "multisite-summary.json").write_text(json.dumps(SUMMARY, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    (TRANSPORT / "ssl-labs-api.json").write_text(json.dumps(EVENTS, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "multisite-summary.json").write_text(json.dumps(SUMMARY, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
