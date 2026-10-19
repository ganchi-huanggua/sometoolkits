#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    echo "Run this script with bash instead of sourcing it." >&2
    return 1
fi

set -euo pipefail

BASE_DIR="/liuhezhao"
PROXY_DIR="$BASE_DIR/proxy"
MIHOMO_NAME="mihomo-linux-amd64-v3-v1.19.28"
MIHOMO_BIN="/usr/local/bin/mihomo"
CONDA_BIN="$BASE_DIR/miniconda3/bin/conda"
CONFIG_DIR="$HOME/.config/mihomo"
BASHRC="$HOME/.bashrc"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Run with bash, not source. Modules run in isolated subshells.
# Errors stop later modules; already completed changes are not rolled back.

# Check the key input before making installation changes.
if [[ ! -s "$SCRIPT_DIR/public.txt" ]]; then
    echo "Public key file is missing or empty: $SCRIPT_DIR/public.txt" >&2
    exit 1
fi

# ======================================================================
# 1. Install mihomo and validate configuration
# ======================================================================
(
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
)

# ======================================================================
# 2. Initialize Conda and configure Bash environment
# ======================================================================
(
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

    printf "Bash configuration backup: %s\n" "$BACKUP"
)

# ======================================================================
# 3. Configure Git identity and GitHub SSH authentication
# ======================================================================
(
    # Configure Git commit identity.
    git config --global user.email "liuhezhao0616@163.com"
    git config --global user.name "ganchi-huanggua"

    SSH_DIR="$HOME/.ssh"
    KEY_FILE="$SSH_DIR/id_ed25519_github"
    SSH_CONFIG="$SSH_DIR/config"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # Generate a dedicated key without overwriting existing files.
    if [[ -f "$KEY_FILE" ]]; then
        echo "Using existing SSH key: $KEY_FILE"
    elif [[ -e "$KEY_FILE.pub" ]]; then
        echo "Public key exists, but private key is missing: $KEY_FILE" >&2
        exit 1
    else
        ssh-keygen -t ed25519 -f "$KEY_FILE" -C "liuhezhao0616@163.com"
    fi
    chmod 600 "$KEY_FILE"

    # Restore the public key from the existing private key if needed.
    if [[ ! -f "$KEY_FILE.pub" ]]; then
        PUBLIC_KEY=$(ssh-keygen -y -f "$KEY_FILE")
        printf '%s\n' "$PUBLIC_KEY" > "$KEY_FILE.pub"
    fi
    chmod 644 "$KEY_FILE.pub"

    # Preserve an existing explicit GitHub host configuration.
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    if awk '
        tolower($1) == "host" {
            for (i = 2; i <= NF; i++) {
                if (tolower($i) == "github.com") {
                    found = 1
                }
            }
        }
        END { exit !found }
    ' "$SSH_CONFIG"; then
        echo "Existing GitHub SSH configuration preserved."
        echo "Check that it uses: $KEY_FILE"
    else
        cp -p "$SSH_CONFIG" \
            "$SSH_CONFIG.bak.$(date +%Y%m%d-%H%M%S).$$"
        SSH_TEMP=$(mktemp "$SSH_DIR/config.tmp.XXXXXX")
        trap 'rm -f "$SSH_TEMP"' EXIT

        # Place host-specific settings before wildcard defaults.
        {
            cat <<'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes

EOF
            cat "$SSH_CONFIG"
        } > "$SSH_TEMP"
        cat "$SSH_TEMP" > "$SSH_CONFIG"
    fi

    printf '\nAdd this PUBLIC key to GitHub Settings -> SSH and GPG keys:\n\n'
    cat "$KEY_FILE.pub"
)

# ======================================================================
# 4. Import public keys for root SSH login
# ======================================================================
(
    umask 077

    PUBLIC_KEY_FILE="$SCRIPT_DIR/public.txt"
    AUTH_DIR="/root/.ssh"
    AUTH_FILE="$AUTH_DIR/authorized_keys"

    if [[ ! -s "$PUBLIC_KEY_FILE" ]]; then
        echo "Public key file is missing or empty: $PUBLIC_KEY_FILE" >&2
        exit 1
    fi

    mkdir -p "$AUTH_DIR"
    chmod 700 "$AUTH_DIR"

    if [[ -f "$AUTH_FILE" ]]; then
        cp -p "$AUTH_FILE" \
            "$AUTH_FILE.bak.$(date +%Y%m%d-%H%M%S).$$"
    fi

    touch "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"

    # Ensure existing content ends with a newline.
    if [[ -s "$AUTH_FILE" ]] &&
        [[ -n "$(tail -c 1 "$AUTH_FILE")" ]]; then
        printf '\n' >> "$AUTH_FILE"
    fi

    ADDED=0

    while IFS= read -r KEY || [[ -n "$KEY" ]]; do
        # Remove Windows CRLF line endings.
        KEY="${KEY%$'\r'}"

        [[ "$KEY" =~ ^[[:space:]]*$ ]] && continue
        [[ "$KEY" =~ ^[[:space:]]*# ]] && continue

        if ! grep -qxF -- "$KEY" "$AUTH_FILE"; then
            printf '%s\n' "$KEY" >> "$AUTH_FILE"
            ADDED=$((ADDED + 1))
        fi
    done < "$PUBLIC_KEY_FILE"

    echo "Added $ADDED public key(s) to $AUTH_FILE"
)

# Report completion only after every module succeeds.
cat <<'EOF'

Setup completed. Mihomo was validated but not started.

Run in your current terminal:
    source ~/.bashrc
    tmux new -s mihomo
    tmux source-file /liuhezhao/proxy/.tmux.conf
Start mihomo inside tmux:
    mihomo ~/.config/mihomo -f ~/.config/mihomo/config.yaml

Detach with Ctrl+b, then d. Enable proxy variables with proxy_on.
Add the printed GitHub public key to your GitHub account, then test:
    ssh -T git@github.com
EOF
