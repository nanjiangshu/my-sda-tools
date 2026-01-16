#!/bin/bash

# --- Configuration & Defaults ---
BUCKET="s3://public-metadata"
LOCAL_BACKUP_DIR="./local_backup_landing_page"
S3_CONFIG="s3cmd-bp-master-metadata.conf"
DRY_RUN=false
KEYFILE=""

# --- Functions ---

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Synchronizes .c4gh files from S3, decrypts them locally, and replaces 
the remote encrypted files with decrypted versions.

Options:
  -c, --config PATH    Path to s3cmd config file (default: $S3_CONFIG)
  --dry-run            Show what would be done without making changes
  -h, --help           Display this help message

Requirements:
  - s3cmd, crypt4gh, and vault must be installed and authenticated.
EOF
    exit 0
}

validate_env() {
    if [[ ! -f "$S3_CONFIG" ]]; then
        echo "Error: S3CMD config file not found: $S3_CONFIG"
        exit 1
    fi

    if ! command -v s3cmd &> /dev/null || ! command -v crypt4gh &> /dev/null || ! command -v vault &> /dev/null; then
        echo "Error: Required tools (s3cmd, crypt4gh, vault) are not in PATH."
        exit 1
    fi

    # Add this to the top of your script
    if ! crypt4gh --help | grep -q "\-s, \-\-seckey"; then
        echo "Error: The 'crypt4gh' in your PATH is not the Go version."
        echo "The Go version is required for the -s and -f syntax."
        exit 1
    fi
}

setup_secrets() {
    echo "Retrieving secrets from Vault..."
    RAND_ID=$((RANDOM % 10000))
    KEYFILE="c4gh.sec.${RAND_ID}.pem"

    # Attempt to retrieve key and password
    if ! vault kv get -field=private_key bp-secrets/crypt4gh > "$KEYFILE" 2>/dev/null; then
        echo "Error: Unable to retrieve private key from Vault."
        exit 1
    fi

    export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh 2>/dev/null)

    if [[ -z "$C4GH_PASSPHRASE" ]]; then
        echo "Error: Could not retrieve passphrase."
        rm -f "$KEYFILE"
        exit 1
    fi
}

cleanup() {
    if [[ -f "$KEYFILE" ]]; then
        echo "Cleaning up temporary keyfile..."
        rm -f "$KEYFILE"
    fi
    unset C4GH_PASSPHRASE
}

main_process() {
    echo "Listing files in $BUCKET using config $S3_CONFIG..."
    local files
    files=$(s3cmd -c "$S3_CONFIG" ls -r "$BUCKET" | awk '{print $4}')

    for s3_path in $files; do
        # Skip directories and non-c4gh files
        [[ $s3_path == */ ]] && continue
        [[ $s3_path != *.c4gh ]] && continue

        local relative_path=${s3_path#$BUCKET/}
        local local_file="$LOCAL_BACKUP_DIR/$relative_path"
        local local_dir=$(dirname "$local_file")
        local decrypted_local_file="${local_file%.c4gh}"
        local decrypted_s3_path="${s3_path%.c4gh}"

        echo "---------------------------------------------------"
        echo "Processing: $relative_path"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[Dry-Run] Would download $s3_path"
            echo "[Dry-Run] Would decrypt to $(basename "$decrypted_local_file")"
            echo "[Dry-Run] Would upload to $decrypted_s3_path"
            echo "[Dry-Run] Would delete $s3_path"
        else
            mkdir -p "$local_dir"
            
            # 1. Download
            s3cmd -c "$S3_CONFIG" get "$s3_path" "$local_file" --force > /dev/null

            # 2. Decrypt
            echo "Decrypting..."
            if crypt4gh decrypt -s "$KEYFILE" -f "$local_file"; then
                # 3. Upload Decrypted
                if [ ! -f "$decrypted_local_file" ]; then
                    echo "❌ Decrypted file not found: $decrypted_local_file"
                    continue
                fi
                echo "Uploading decrypted version..."
                s3cmd -c "$S3_CONFIG" put "$decrypted_local_file" "$decrypted_s3_path"
                
                # 4. Remove Encrypted
                echo "Removing encrypted file from S3..."
                s3cmd -c "$S3_CONFIG" rm "$s3_path"
            else
                echo "❌ Decryption failed for $local_file"
            fi
        fi
    done
}

# --- Script Execution ---

# Trap cleanup to ensure sensitive key is deleted even if script is interrupted (Ctrl+C)
trap cleanup EXIT

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        -c|--config) S3_CONFIG="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo "--- DRY RUN MODE ENABLED ---"
fi

# Run logic
validate_env
setup_secrets
main_process

echo "---------------------------------------------------"
echo "Task Complete."