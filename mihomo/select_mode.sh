#!/usr/bin/env bash
set -euo pipefail

API="${MIHOMO_API:-http://127.0.0.1:9090}"
MODE="${1:-}"

if [[ -z "$MODE" ]]; then
	    echo "1) rule"
	        echo "2) global"
		    echo "3) direct"
		        read -r -p "Select mode [1-3]: " MODE
fi

case "$MODE" in
	    1|rule)   MODE="rule" ;;
	        2|global) MODE="global" ;;
		    3|direct) MODE="direct" ;;
		        *)
				        echo "Usage: bash switch_mode.sh [rule|global|direct]" >&2
					        exit 1
						        ;;
					esac

					if [[ -z "${MIHOMO_SECRET+x}" ]]; then
						    read -r -s -p "Enter API secret (leave blank if none): " MIHOMO_SECRET
						        printf '\n'
					fi

					export MIHOMO_SECRET

					python - "$API" "$MODE" <<'PY'
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

api = sys.argv[1].rstrip("/")
mode = sys.argv[2]
secret = os.environ.get("MIHOMO_SECRET", "")
opener = build_opener(ProxyHandler({}))
headers = {"Content-Type": "application/json"}

if secret:
    headers["Authorization"] = f"Bearer {secret}"

def request(method, payload=None):
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = Request(
        api + "/configs",
        data=body,
        headers=headers,
        method=method,
    )
    with opener.open(req, timeout=10) as response:
        content = response.read()
        return json.loads(content) if content else None

try:
    previous = request("GET").get("mode", "unknown")
    request("PATCH", {"mode": mode})
    current = request("GET").get("mode", "unknown")

    if current.lower() != mode:
        raise SystemExit(f"Verification failed. Current mode: {current}")

    print(f"Mode: {previous} -> {current}")

    if mode == "global":
        print("GLOBAL keeps its existing selection, which may be DIRECT.")

except HTTPError as error:
    raise SystemExit(f"HTTP error: {error.code} {error.reason}")
except URLError as error:
    raise SystemExit(f"Connection error: {error.reason}")
except (ValueError, OSError) as error:
    raise SystemExit(f"Error: {error}")
PY
