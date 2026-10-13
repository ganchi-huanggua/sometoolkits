#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/liuhezhao"
PROXY_DIR="$BASE_DIR/proxy"
MIHOMO_NAME="mihomo-linux-amd64-v3-v1.19.28"
MIHOMO_BIN="/usr/local/bin/mihomo"
CONDA_BIN="$BASE_DIR/miniconda3/bin/conda"
CONFIG_DIR="$HOME/.config/mihomo"
BASHRC="$HOME/.bashrc"

cd "$PROXY_DIR"

# Check required files.
[[ -f "$PROXY_DIR/Country.mmdb" ]] || {
    echo "Missing file: $PROXY_DIR/Country.mmdb" >&2
    exit 1
}

[[ -x "$CONDA_BIN" ]] || {
    echo "Conda not found: $CONDA_BIN" >&2
    exit 1
}

# Extract the binary while preserving the archive.
if [[ -f "$MIHOMO_NAME.gz" ]]; then
    gzip -dc "$MIHOMO_NAME.gz" > "$MIHOMO_NAME"
elif [[ ! -f "$MIHOMO_NAME" ]]; then
    echo "Missing mihomo archive or binary in $PROXY_DIR" >&2
    exit 1
fi

# Install mihomo.
install -m 755 "$MIHOMO_NAME" "$MIHOMO_BIN"
"$MIHOMO_BIN" -v

mkdir -p "$CONFIG_DIR"

# Read the subscription URL without displaying it.
read -r -s -p "Enter the mihomo subscription URL: " SUB_URL
printf '\n'

[[ -n "$SUB_URL" ]] || {
    echo "The subscription URL cannot be empty." >&2
    exit 1
}

# Download and validate before replacing the existing configuration.
TEMP_CONFIG=$(mktemp "$CONFIG_DIR/config.download.XXXXXX")
trap 'rm -f "$TEMP_CONFIG"' EXIT

curl -fL --connect-timeout 15 --max-time 120 \
    "$SUB_URL" -o "$TEMP_CONFIG"

cp "$PROXY_DIR/Country.mmdb" "$CONFIG_DIR/Country.mmdb"

"$MIHOMO_BIN" -t -d "$CONFIG_DIR" -f "$TEMP_CONFIG"

if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
    cp -p "$CONFIG_DIR/config.yaml" \
        "$CONFIG_DIR/config.yaml.bak.$(date +%Y%m%d-%H%M%S).$$"
fi

mv "$TEMP_CONFIG" "$CONFIG_DIR/config.yaml"

# Back up .bashrc before initializing Conda.
touch "$BASHRC"
BACKUP="${BASHRC}.bak.$(date +%Y%m%d-%H%M%S).$$"
cp -p "$BASHRC" "$BACKUP"

"$CONDA_BIN" init bash

# Replace the configuration block managed by this script.
sed -i '/^# >>> liuhezhao environment >>>$/,/^# <<< liuhezhao environment <<<$/{d;}' \
    "$BASHRC"

cat >> "$BASHRC" <<'EOF'

# >>> liuhezhao environment >>>
proxy_on() {
    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="$http_proxy"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$http_proxy"
    export all_proxy="$http_proxy"
    export ALL_PROXY="$http_proxy"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="$no_proxy"
    echo "proxy ON: 127.0.0.1:7890"
}

proxy_off() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    unset all_proxy ALL_PROXY no_proxy NO_PROXY
    echo "proxy OFF"
}

# Add tmux to PATH without duplicate entries.
case ":$PATH:" in
    *:/liuhezhao/tmux/bin:*) ;;
    *) export PATH="/liuhezhao/tmux/bin:$PATH" ;;
esac

export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"
# <<< liuhezhao environment <<<
EOF

# Validate the final configuration without starting the proxy service.
"$MIHOMO_BIN" -t -d "$CONFIG_DIR" -f "$CONFIG_DIR/config.yaml"

printf '\nSetup completed. Mihomo was not started.\n'
printf 'Bash configuration backup: %s\n' "$BACKUP"

cat <<'EOF'

Run the following commands in your terminal:

    source ~/.bashrc
    tmux new -s mihomo

Then start mihomo inside the tmux session:

    mihomo -d ~/.config/mihomo -f ~/.config/mihomo/config.yaml

Press Ctrl+b, release both keys, then press d to detach.

To enable proxy variables in another terminal:

    proxy_on
EOF
