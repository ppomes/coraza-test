# Coraza + nginx + OWASP CRS test bench

Docker-based test environment to validate nginx + Coraza WAF with OWASP CRS v4 rules.

Normal requests pass through to nginx (200). Malicious requests are blocked by Coraza (403).

## Dependencies

This build uses three forks with in-progress work not yet merged upstream:

| Project | Fork branch | What it adds |
|---------|------------|--------------|
| [coraza](https://github.com/ppomes/coraza/tree/feat/rules-merge) | `feat/rules-merge` | `WAFWithRules` interface (MergeRules, RulesCount) |
| [libcoraza](https://github.com/ppomes/libcoraza/tree/feat/implement-missing-apis) | `feat/implement-missing-apis` | Actual implementation of `coraza_rules_merge`, `coraza_rules_count`, `coraza_update_status_code` (were stubs) |
| [coraza-nginx](https://github.com/ppomes/coraza-nginx/tree/chore/update-latest-libcoraza) | `chore/update-latest-libcoraza` | Config inheritance, delayed header forwarding, intervention handling fixes |

## Build & run

```bash
# Build from GitHub directly
docker build -t coraza-test https://github.com/ppomes/coraza-test.git

# Or clone first
git clone https://github.com/ppomes/coraza-test.git
docker build -t coraza-test coraza-test/

# Run
docker run -d -p 8080:80 --name coraza-test coraza-test
```

## Test

```bash
# Normal request → 200
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# 200

# SQL injection → 403 (blocked by Coraza, CRS rule 942100)
curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?id=1%20OR%201=1"
# 403

# XSS → 403 (blocked by Coraza, CRS rule 941100)
curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?q=<script>alert(1)</script>"
# 403

# Path traversal → 403 (blocked by Coraza, CRS rule 930100)
curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?file=../../../etc/passwd"
# 403

# Or run the full test suite
./test.sh
```

## What doesn't work without these forks

| Combination | Result |
|-------------|--------|
| Official `corazawaf/libcoraza` master + `corazawaf/coraza-nginx` main | **Does not compile** — API mismatch between libcoraza and the nginx module |
| Official `corazawaf/libcoraza` master + Felipe's PR#3 (`corazawaf/coraza-nginx` `chore/update-latest-libcoraza`) | **Compiles but WAF is inert** — all requests return 200, no blocking, no audit log. The C API functions are stubs that do nothing. |
| ppomes forks (this Dockerfile) | **Works** — normal requests return 200, SQLi/XSS/path traversal all blocked (403) with proper CRS rule IDs in the audit log |

## Logs

```bash
# Coraza audit log (blocked requests with rule details)
docker exec coraza-test cat /var/log/coraza/audit.log

# nginx error log
docker exec coraza-test cat /var/log/nginx/error.log
```

## Cleanup

```bash
docker rm -f coraza-test
docker rmi coraza-test
```
