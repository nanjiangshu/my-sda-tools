#!/bin/bash
set -euo pipefail

# Configuration and Defaults
s3cmdconf=/data3/project-sda/misc/bp-submission/s3cmd-bp-master-archive.conf
binpath=/data3/project-sda/my-sda-tools/scripts/
keyfile=c4gh.sec.pem
outdir=.

usage="
Usage: $0 [OPTIONS] <fileid1> [fileid2] ...
Options:
  -h, --help         Show this help message and exit
  -s3cmdconf <path>  Path to the s3cmd configuration file (default: $s3cmdconf)
  -binpath <path>    Path to the scripts directory (default: $binpath)
  -c4ghkey <path>    Path to the c4gh private key file (default: $keyfile)
  -outdir <path>     Output directory (default: current directory)
"

# --- Function Definition (Must come BEFORE the loop) ---

RetrieveFile(){
    local fileid=$1
    if [[ -z "$fileid" ]]; then
        echo "Error: Empty file ID provided."
        return 1 
    fi
    echo "--- Processing file ID: $fileid ---"

    # 1. Get the header. 
    # Using 'if !' ensures that if the script fails, we can catch it manually 
    # rather than having the whole script crash due to 'set -e'.
    if ! bash "$binpath/get_header_using_fileid.sh" "$fileid" | xxd -r -p > "$tmpdir/$fileid.header.bin"; then
        echo "Error: Failed to retrieve or convert header for $fileid"
        return 1
    fi

    # 2. Attempt retrieval from the first S3 bucket
    echo "Attempting download from archive-2024-01..."
    if ! s3cmd -c "$s3cmdconf" get "s3://archive-2024-01/$fileid" "$tmpdir/$fileid.newstorage"; then
        echo "File not found in 2024-01 bucket. Trying archive-2025-11..."
        
        # 3. Fallback: Attempt retrieval from the second S3 bucket
        if ! s3cmd -c "$s3cmdconf" get "s3://archive-2025-11/$fileid" "$tmpdir/$fileid.newstorage"; then
            echo "Error: File $fileid could not be found in either bucket."
            return 1
        fi
    fi

    # 4. Verify the file actually has content before proceeding
    if [ ! -s "$tmpdir/$fileid.newstorage" ]; then
        echo "Error: Retrieved file $fileid is empty (0 bytes)."
        return 1
    fi

    # 5. Concatenate and Decrypt
    cat "$tmpdir/$fileid.header.bin" "$tmpdir/$fileid.newstorage" > "$tmpdir/$fileid.c4gh"
    
    # Optional: Backup the encrypted combined file
    cp "$tmpdir/$fileid.c4gh" "$outdir/$fileid.bak.c4gh"
    
    echo "Decrypting $fileid..."
    if ! crypt4gh decrypt -s "$keyfile" -f "$tmpdir/$fileid.c4gh" ; then
        echo "Error: Decryption failed for $fileid. Check your passphrase or key."
        return 1
    fi
    mv "$tmpdir/$fileid" "$outdir/$fileid"

    echo "Success: $fileid is ready in $outdir"
}

# --- Argument Parsing ---

if [ "$#" -eq 0 ]; then
    echo "$usage"
    exit 1
fi

file_ids=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "$usage"
            exit 0
            ;;
        -s3cmdconf)
            s3cmdconf="$2"; shift 2
            ;;
        -binpath)
            binpath="$2"; shift 2
            ;;
        -c4ghkey)
            keyfile="$2"; shift 2
            ;;
        -outdir)
            outdir="$2"
            mkdir -p "$outdir"
            shift 2
            ;;
        *)
            file_ids+=("$1")
            shift
            ;;
    esac
done

# --- Validations ---

if [ ! -f "$s3cmdconf" ]; then
    echo "S3CMD config file not found: $s3cmdconf"
    exit 1
fi

if [ ! -f "$binpath/get_header_using_fileid.sh" ]; then
    echo "Script not found: $binpath/get_header_using_fileid.sh"
    exit 1
fi

# Vault retrieval
if ! vault kv get -field=private_key bp-secrets/crypt4gh > /dev/null 2>&1; then
  echo "Error: Unable to retrieve private key from Vault."
  exit 1
fi

vault kv get -field=private_key bp-secrets/crypt4gh > "$keyfile"
export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh)

# --- Main Execution ---

tmpdir=$(mktemp -d)
# Clean up temp files AND the sensitive keyfile on exit
trap 'rm -rf "$tmpdir"; rm -f "$keyfile"' EXIT

for fileid in "${file_ids[@]}"; do
    RetrieveFile "$fileid"
done