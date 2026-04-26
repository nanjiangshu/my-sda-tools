#!/bin/bash

# decrypt .c4gh file downloaded from BP inbox


usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [file1.c4gh file2.c4gh ...]
Options:
  --dry-run            Show what would be done without making changes
  -h, --help           Display this help message

Requirements:
  - crypt4gh, and vault must be installed and authenticated.
EOF
    exit 0
}

validate_env() {
    if ! command -v crypt4gh &> /dev/null || ! command -v vault &> /dev/null; then
        echo "Error: Required tools (crypt4gh, vault) are not in PATH."
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
    for file in "${file_list[@]}"; do
        # Skip directories and non-c4gh files
        [[ $file == */ ]] && continue
        [[ $file != *.c4gh ]] && continue

        echo "Decrypting $file"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "Would decrypt $file using key from $KEYFILE"
        else
            echo "Decrypting..."
            if ! crypt4gh decrypt -s "$KEYFILE" -f "$file"; then
                echo "❌ Decryption failed for $file"
            fi
        fi
    done
}

# Trap cleanup to ensure sensitive key is deleted even if script is interrupted (Ctrl+C)
trap cleanup EXIT

# Parse Arguments
file_list=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        *) file_list+=("$1") ;;
    esac
    shift
done

if [[ ${#file_list[@]} -eq 0 ]]; then
    echo "Error: No input files provided."
    usage
fi

# Run logic
validate_env
setup_secrets
main_process