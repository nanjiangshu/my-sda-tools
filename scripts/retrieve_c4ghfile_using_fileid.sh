#!/bin/bash
set -euo pipefail

# Configuration and Defaults
s3cmdconf=$HOME/.sda/s3cmd-bp-master-archive.conf
SCRIPT_PATH=$(dirname "$0")
outdir=.
mapfile=""

usage="
Usage: $0 [OPTIONS] <fileid1> [fileid2] ... [-mapfile MAPFILE]

Provide either fileids or a map file containing them.
The mapfile is a list of fileids and filepath, one per line.

Options:
  -h, --help         Show this help message and exit
  -s3cmdconf <path>  Path to the s3cmd configuration file (default: $s3cmdconf)
  -outdir <path>     Output directory (default: current directory)
  -mapfile <path>       Path to the map file (default: none)
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
    if ! bash "$SCRIPT_PATH/get_header_using_fileid.sh" "$fileid" | xxd -r -p > "$tmpdir/$fileid.header.bin"; then
        echo "Error: Failed to retrieve or convert header for $fileid"
        return 1
    fi

    # 2. Attempt retrieval from the first S3 bucket
    # List all archive buckets and try to retrieve the file from each until successful
    BUCKETS=($(s3cmd -c "$s3cmdconf" ls s3:// | grep "/\<archive.[0-9]\>" | awk '{print $3}' | sed 's/s3:\/\///' | sort -r))
    BUCKETS+=("archive-2024-01")
    BUCKETS+=("archive-2025-11")
    # loop through the buckets in reverse order (archive.2, archive.1, etc.)
    for bucket in "${BUCKETS[@]}"; do
        echo "Attempting download from $bucket"
        if s3cmd -c "$s3cmdconf" get "s3://${bucket}/${fileid}" "$tmpdir/$fileid.newstorage"; then
            echo "Success: Retrieved $fileid from $bucket"
            break
        else
            echo "Warning: File $fileid not found in $bucket. Trying next bucket..."
        fi
    done

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
        -outdir)
            outdir="$2"
            mkdir -p "$outdir"
            shift 2
            ;;
        -mapfile)
            mapfile="$2"
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

if [ ! -f "$SCRIPT_PATH/get_header_using_fileid.sh" ]; then
    echo "Script not found: $SCRIPT_PATH/get_header_using_fileid.sh"
    exit 1
fi

# Vault retrieval
if ! vault kv get -field=private_key bp-secrets/crypt4gh > /dev/null 2>&1; then
  echo "Error: Unable to retrieve private key from Vault."
  exit 1
fi


# --- Main Execution ---

tmpdir=$(mktemp -d)
keyfile="$tmpdir/c4gh.sec.pem"

vault kv get -field=private_key bp-secrets/crypt4gh > "$tmpdir/c4gh.sec.pem"
export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh)
# Clean up temp files AND the sensitive key on exit
trap 'rm -rf "$tmpdir"' EXIT

# when a mapfile is provided, read fileids from the mapfile and then use the
# script map_fileid_to_filepath.sh to store files in the appropriate locations based on the map file

if [[ -n "$mapfile" ]]; then
    while IFS= read -r line; do
        fileid=$(echo "$line" | awk '{print $1}')
        RetrieveFile "$fileid"
    done < "$mapfile"
    bash "$SCRIPT_PATH/map_fileid_to_filepath.sh" -m "$mapfile" -s "$outdir" -o "$outdir"
    echo "Files have been organized based on the map file and output to $outdir."
else
    for fileid in "${file_ids[@]}"; do
        RetrieveFile "$fileid"
    done
    echo "Files have been retrieved and are available in $outdir."
fi
