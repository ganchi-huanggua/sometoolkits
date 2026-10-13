#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:9090"
GROUP='\U0001F530 \u9009\u62E9\u8282\u70B9'
NODE_INDEX=3

# Use MIHOMO_SECRET if provided; otherwise prompt for it.
if [[ -z "${MIHOMO_SECRET+x}" ]]; then
    read -r -s -p "Enter the mihomo API secret (leave blank if none): " MIHOMO_SECRET
    printf '\n'
fi

export MIHOMO_SECRET

python - "$API" "$GROUP" "$NODE_INDEX" <<'PY'
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import ProxyHandler, Request, build_opener

api, group, index_text = sys.argv[1:]
group = group.encode("ascii").decode("unicode_escape")
index = int(index_text)
secret = os.environ.get("MIHOMO_SECRET", "")

# Access the local controller directly.
opener = build_opener(ProxyHandler({}))
url = f"{api.rstrip('/')}/proxies/{quote(group, safe='')}"
headers = {"Content-Type": "application/json"}

if secret:
    headers["Authorization"] = f"Bearer {secret}"

def request(method, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(url, data=body, headers=headers, method=method)
    with opener.open(req, timeout=10) as response:
        data = response.read()
        return json.loads(data) if data else None

try:
    info = request("GET")

    if info.get("type") != "Selector":
        raise SystemExit("The target group is not a manual selector.")

    nodes = info.get("all", [])
    if not 0 <= index < len(nodes):
        raise SystemExit(
            f"Index {index} is out of range. Available options: {len(nodes)}"
        )

    node = nodes[index]
    request("PUT", {"name": node})

    current = request("GET").get("now")
    if current != node:
        raise SystemExit("Verification failed: the selection does not match.")

    print(f"Selected index: {index}")
    print("Node: " + json.dumps(current, ensure_ascii=True))

except HTTPError as error:
    raise SystemExit(f"HTTP error: {error.code} {error.reason}")
except URLError as error:
    raise SystemExit(f"Connection error: {error.reason}")
except (ValueError, OSError) as error:
    raise SystemExit(f"Error: {error}")
PY
