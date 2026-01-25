#!/usr/bin/env bash
setup_sda_kubeconfig() {
    local ENV_NAME="fega-v2"
    local SDA_DIR="$HOME/.sda"
    local KEY_FILE="$SDA_DIR/fega-private.pem"
    local KUBECONFIG_FILE="$SDA_DIR/kubeconfig_fega.yaml"
    local SCRIPT_PATH=""
    local TMP_BIN_DIR=$(mktemp -d)

    if [[ -d "/data3/project-sda" ]]; then
        SCRIPT_PATH="/data3/project-sda/LocalEGA-SE-Deployment/production/fega_v2/cluster/scripts/get_kubeconfig.sh"
    elif [[ -d "$HOME/project-sda" ]]; then
        SCRIPT_PATH="$HOME/project-sda/LocalEGA-SE-Deployment/production/fega_v2/cluster/scripts/get_kubeconfig.sh"
    else
        echo "❌ ERROR: LocalEGA-SE-Deployment directory not found in /data3 or $HOME"
        rm -rf "$TMP_BIN_DIR"
        return 1
    fi

    # 2. macOS Compatibility
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v gbase64 >/dev/null 2>&1; then
            ln -s "$(command -v gbase64)" "$TMP_BIN_DIR/base64"
        else
            echo "❌ ERROR: gbase64 not found. Run: brew install coreutils"
            rm -rf "$TMP_BIN_DIR"
            return 1
        fi
    fi

    mkdir -p "$SDA_DIR"

    # 3. Execution Block
    # We use a subshell to keep the PATH and Directory changes local
    (
        export PATH="$TMP_BIN_DIR:$PATH"
        cd "$SDA_DIR" || exit 1
        
        # Execute the script normally (preserves $0 and relative paths)
        bash "$SCRIPT_PATH" "$ENV_NAME" "$KEY_FILE"
        
        if [[ -f "kubeconfig.yaml" ]]; then
            chmod 600 "kubeconfig.yaml"
            mv "kubeconfig.yaml" "$KUBECONFIG_FILE"
        else
            echo "❌ ERROR: kubeconfig.yaml was not created by the source script."
            exit 1
        fi
    )
    local EXIT_CODE=$?

    # Cleanup temp bin
    rm -rf "$TMP_BIN_DIR"

    if [ $EXIT_CODE -eq 0 ]; then
        export KUBECONFIG="$KUBECONFIG_FILE"
        echo "✅ KUBECONFIG set to $KUBECONFIG"
    else
        echo "❌ ERROR: Failed to set up KUBECONFIG."
        return 1
    fi
}

# Guard: must be sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "ERROR: source this script, do not run it:"
    echo "  source $0"
    exit 1
else
    setup_sda_kubeconfig
    unset -f setup_sda_kubeconfig
fi