#!/bin/bash

# decrypt .c4gh file downloaded from BP inbox


usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [file1.c4gh file2.c4gh ...]
Options:
  -l, --list FILE      Read the files to decrypt from FILE, one per line
                       ('-' for stdin). Empty lines and lines starting with
                       '#' are ignored.
  --dry-run            Show what would be done without making changes
  -h, --help           Display this help message

If no files are given and the input is piped, the file list is read from stdin, e.g.
  find outdir -name '*.c4gh' | $(basename "$0")

Requirements:
  - crypt4gh, and vault must be installed and authenticated.
EOF
    exit "${1:-0}"
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
    # Private key file only readable by the current user
    KEYFILE=$(umask 077 && mktemp "${TMPDIR:-/tmp}/c4gh.sec.XXXXXX")

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
            if ! crypt4gh decrypt -s "$KEYFILE" -f "$file" </dev/null; then
                echo "❌ Decryption failed for $file"
                failed_list+=("$file")
            fi
        fi
    done
}

read_list() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
        file_list+=("$line")
    done
}

# Trap cleanup to ensure sensitive key is deleted even if script is interrupted (Ctrl+C)
trap cleanup EXIT

# Parse Arguments
file_list=()
failed_list=()
LIST_FILE=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -l|--list)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option $1 requires an argument."
                usage 1
            fi
            LIST_FILE="$2"
            shift
            ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        -?*)
            echo "Error: Invalid option $1."
            usage 1
            ;;
        *) file_list+=("$1") ;;
    esac
    shift
done

# Read the whole list before decrypting, so that nothing else reads from stdin
if [[ "$LIST_FILE" == "-" ]]; then
    read_list
elif [[ -n "$LIST_FILE" ]]; then
    if [[ ! -f "$LIST_FILE" ]]; then
        echo "Error: List file '$LIST_FILE' not found."
        exit 1
    fi
    read_list < "$LIST_FILE"
elif [[ ${#file_list[@]} -eq 0 && ! -t 0 ]]; then
    read_list
fi

if [[ ${#file_list[@]} -eq 0 ]]; then
    echo "Error: No input files provided."
    usage 1
fi

# Run logic
validate_env
setup_secrets
main_process

if [[ ${#failed_list[@]} -gt 0 ]]; then
    echo "❌ Decryption failed for ${#failed_list[@]} file(s):"
    printf '    - %s\n' "${failed_list[@]}"
    exit 1
fi