#!/bin/bash

set -euo pipefail

# this script downloads metadata files for a given dataset ID s3cmd

usage="""
Usage: $0 [-outdir] OUTDIR dataset_id1 dataset_id2 ...

-s3cmdFile FILE   Path to s3cmd config file (default: s3cmd-bp-master-private.conf)
-h, --help       Show this help message

"""

s3cmdFile="s3cmd-bp-master-private.conf"
keyfile="c4gh.sec.pem"

if [ $# -lt 2 ]; then
  echo "$usage"
  exit 1
fi
dataset_ids=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -outdir) shift; outdir="$1" ;;
        -s3cmdFile) shift; s3cmdFile="$1" ;;
        -h|--help)  echo "$usage"; exit 0 ;;
        *) dataset_ids+=("$1") ;;
    esac
    shift
done
outdir="${outdir:-.}"
mkdir -p "$outdir"
if [[ ! -d "$outdir" ]]; then
  echo "Error: $outdir is not a directory."
  exit 1
fi

if ! vault kv get -field=private_key bp-secrets/crypt4gh > /dev/null 2>&1; then
  echo "Error: Unable to retrieve private key from Vault. Ensure you are logged in and have access."
  exit 1
fi

vault kv get -field=private_key bp-secrets/crypt4gh > $keyfile 
export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh)

metafileList="$outdir/metadata_files.txt"
s3cmd -c $s3cmdFile ls -r  s3://metadata-2024-01 | awk '{print $4}'> $metafileList

for dataset_id in "${dataset_ids[@]}"; do
  echo "Processing dataset ID: $dataset_id"
  mkdir -p "$outdir/$dataset_id"
  grep "$dataset_id" $metafileList | while read -r metafile; do
    basename=$(basename "$metafile")
    echo "  Downloading $metafile"
    s3cmd -c $s3cmdFile get "$metafile" "$outdir/$dataset_id/"
    crypt4gh_file="$outdir/$dataset_id/$basename"
    if [[ -f "$crypt4gh_file" ]]; then
      echo "  Decrypting $crypt4gh_file"
      crypt4gh decrypt -s $keyfile -f $crypt4gh_file 
    else
      echo "  Warning: Downloaded file not found: $crypt4gh_file"
    fi
  done
done

