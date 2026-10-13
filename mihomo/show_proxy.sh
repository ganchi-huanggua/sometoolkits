#!/usr/bin/env bash
set -euo pipefail

API="${MIHOMO_API:-http://127.0.0.1:9090}"

if [[ -z "${MIHOMO_SECRET+x}" ]]; then
	    read -r -s -p "Enter API secret (leave blank if none): " MIHOMO_SECRET
	        printf '\n'
fi

export MIHOMO_SECRET

python - "$API" <<'PY'
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

api = sys.argv[1].rstrip("/")
secret = os.environ.get("MIHOMO_SECRET", "")
opener = build_opener(ProxyHandler({}))
headers = {}

if secret:
    headers["Authorization"] = f"Bearer {secret}"

def get(path):
    request = Request(api + path, headers=headers)
    with opener.open(request, timeout=10) as response:
        return json.load(response)

def display(text):
    return str(text).encode("ascii", "backslashreplace").decode("ascii")

try:
    mode = get("/configs").get("mode", "unknown").lower()
    print("Mode:", mode)

    if mode == "direct":
        print("Selected: DIRECT")
        sys.exit(0)

    if mode not in ("global", "rule"):
        raise SystemExit("Unknown mode; cannot determine selection.")

    proxies = get("/proxies")["proxies"]
    name = (
        "GLOBAL" if mode == "global"
        else "\U0001f530 \u9009\u62e9\u8282\u70b9"
    )

    if name not in proxies:
        raise SystemExit("Target proxy group not found.")

    chain = []
    visited = set()

    while True:
        if name in visited:
            raise SystemExit("Cycle detected in proxy group selection.")
        visited.add(name)
        chain.append(name)

        info = proxies.get(name, {})
        next_name = info.get("now")
        if not next_name:
            break
        name = next_name

    print("Selected:", " -> ".join(display(item) for item in chain))

    if mode == "rule":
        print("Note: this group applies only to traffic routed through it.")

except HTTPError as error:
    raise SystemExit(f"HTTP error: {error.code} {error.reason}")
except URLError as error:
    raise SystemExit(f"Connection error: {error.reason}")
except (ValueError, KeyError, OSError) as error:
    raise SystemExit(f"Error: {error}")
PY
