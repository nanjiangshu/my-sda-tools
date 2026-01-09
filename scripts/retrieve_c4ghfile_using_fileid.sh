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
    echo "Processing file ID: $fileid"

    # Hex to binary for the header
    bash "$binpath/get_header_using_fileid.sh" "$fileid" | xxd -r -p > "$tmpdir/$fileid.header.bin"
    
    # Attempt S3 retrieval
    s3cmd -c "$s3cmdconf" get "s3://archive-2024-01/$fileid" "$tmpdir/$fileid.newstorage"

    if [ ! -s "$tmpdir/$fileid.newstorage" ]; then
        echo "Error: Retrieved archived file is empty for file ID: $fileid. Trying 2025 bucket..."
        s3cmd -c "$s3cmdconf" get "s3://archive-2025-11/$fileid" "$tmpdir/$fileid.newstorage"
        
        if [ ! -s "$tmpdir/$fileid.newstorage" ]; then
            echo "Error: Retrieved archived file is still empty for file ID: $fileid"
            return 1
        fi
    fi

    # Concatenate and Decrypt
    cat "$tmpdir/$fileid.header.bin" "$tmpdir/$fileid.newstorage" > "$tmpdir/$fileid.c4gh"
    cp "$tmpdir/$fileid.c4gh" "$outdir/$fileid.bak.c4gh"
    
    # Decrypting
    crypt4gh decrypt -s "$keyfile" -f "$tmpdir/$fileid.c4gh" -o "$tmpdir/$fileid.decrypted"

    cp "$tmpdir/$fileid.decrypted" "$outdir/$fileid"
    echo "File retrieved and decrypted successfully: $fileid"
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