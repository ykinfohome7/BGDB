# BGDB Security Scanner

Primary GitHub repository: `ykinfohome7/BGDB` (account BGDB INFO; SSL Labs API contact: `info@bgdb.eu`).

## ChatGPT / Claude Code routing rule

When asked in Bulgarian or English to **scan/check/audit a website** (e.g. `Сканирай money.bg`), consult this scanner first where GitHub is connected, rather than treating the request as a generic web-only check. Confirm the exact hostname and existence before requesting SSL Labs data. If GitHub cannot be accessed or the scanner cannot be run, say so; use ordinary web checks as a clearly labelled fallback, not as a fabricated SSL Labs grade. The repository is not an automatic built-in ChatGPT tool or universal memory.

## Website existence preflight (mandatory)

The scanner validates the hostname, resolves DNS, rejects non-public IP destinations, and checks whether the public HTTPS endpoint answers (including HTTP error or redirect statuses). It writes `reports/preflight/<host>.json`. If DNS/HTTPS cannot be verified, it does not start SSL Labs queries and reports an explicit inconclusive outcome. DNS resolves or HTTPS replies do not, by themselves, mean the site is secure.

## How to scan

GitHub Actions: `.github/workflows/ssllabs-multisite.yml` → **Run workflow** → optional `target_host`. Empty target scans the default examples and owned sites; a hostname scans only that host. GitHub Actions writes:
- `reports/preflight/`: first-contact DNS + HTTPS website existence evidence
- `reports/ssl-labs/`: complete SSL Labs API v4 JSON (certificate, SAN, chain, protocols, cipher suites, named groups, HTTP headers, vulnerabilities and browser simulations when the API provides them)
- `reports/transport/ssl-labs-api.json`: sent, received, HTTP response, errors, retry evidence
- `reports/post-quantum-tls/`: live OpenSSL 3.5+ TLS 1.3 ML-KEM group negotiation probes on owned domains only

Owned: `bgspiritllc.com`, `bgdb.eu`. Reference/example hosts (cached SSL Labs only; never initiate scans of these domains): `google.com`, `yahoo.com`, `meta.com`, `money.bg`. `oni.bg` is **not** in the active example list because the user switched the test to money.bg.

## Report policy

Use the SSL Labs layout as a starting point: overall grade, then **Certificate**, **Protocol Support**, **Key Exchange**, **Cipher Strength**. Follow with detailed sections for SAN/issuer/validity/chain, ciphers and TLS groups, HTTP headers/HSTS, known vulnerability checks, client simulations, and a **separate** post-quantum section. The API returns grades and evidence but does not necessarily expose independent 0–100 scores for the four graphical categories; do not invent scores. Distinguish PQ TLS (hybrid ML-KEM) from photonic QKD; do not claim NIST certification or a universal quantum-safety grade.

A successful GitHub job does not mean every scan completed: inspect the per-domain JSON statuses and last scan timestamps. A cached result is historical evidence, not a freshly initiated scan. When data are absent, say **Not tested / Unknown**, never guess.
