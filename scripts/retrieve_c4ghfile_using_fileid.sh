#!/bin/bash
set -euo pipefail

# This script retrieves c4gh file by concatenation of the header (from sda.files) and the archived file from the archive and then decrypt it 
s3cmdconf=/data3/project-sda/misc/bp-submission/s3cmd-bp-master-archive.conf
binpath=/data3/project-sda/my-sda-tools/scripts/
keyfile=c4gh.sec.pem
outdir=.

usage="""
Usage: $0 [OPTIONS] <fileid1> [fileid2] ...
Options:
  -h, --help        Show this help message and exit
  -s3cmdconf <path> Path to the s3cmd configuration file (default: $s3cmdconf)
  -binpath <path>   Path to the scripts directory (default: $binpath)
  -c4ghkey <path>   Path to the c4gh private key file (default: $keyfile)
  -outdir <path>    Output directory (default: current directory)
"""

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
            shift
            if [ -z "$1" ]; then
                echo "Error: --s3cmdconf requires a path argument."
                exit 1
            fi
            s3cmdconf=$1
            shift
            ;;
        -binpath)
            shift
            if [ -z "$1" ]; then
                echo "Error: --binpath requires a path argument."
                exit 1
            fi
            binpath=$1
            shift
            ;;
        -c4ghkey)
            shift
            if [ -z "$1" ]; then
                echo "Error: --c4ghkey requires a path argument."
                exit 1
            fi
            keyfile=$1
            shift
            ;;
        -outdir)
            shift
            if [ -z "$1" ]; then
                echo "Error: --outdir requires a path argument."
                exit 1
            fi
            outdir=$1
            mkdir -p "$outdir"
            if [[ ! -d "$outdir" ]]; then
              echo "Error: $outdir is not a directory."
              exit 1
            fi
            shift
            ;;
        *)
            file_ids+=("$1")
            shift
            ;;
    esac
done

if [ ! -f $s3cmdconf ];then
    echo "S3CMD config file not found: $s3cmdconf"
    exit 1
fi

if [ ! -f $binpath/get_header_using_fileid.sh ];then
    echo "Script not found: $binpath/get_header_using_fileid.sh"
    exit 1
fi

if ! vault kv get -field=private_key bp-secrets/crypt4gh > /dev/null 2>&1; then
  echo "Error: Unable to retrieve private key from Vault. Ensure you are logged in and have access."
  exit 1
fi

vault kv get -field=private_key bp-secrets/crypt4gh > $keyfile 
export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh)

if [ ! -f $keyfile ];then
    echo "Private key file not found: $keyfile"
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT


for fileid in "${file_ids[@]}"; do
    if [[ -z "$fileid" ]]; then
        echo "Error: Empty file ID provided."
        exit 1
    fi
    echo "Processing file ID: $fileid"

    bash $binpath/get_header_using_fileid.sh $fileid | xxd -r -p > $tmpdir/$fileid.header.bin
    s3cmd -c $s3cmdconf get s3://archive-2024-01/$fileid  $tmpdir/$fileid.newstorage
    cat $tmpdir/$fileid.header.bin $tmpdir/$fileid.newstorage > $tmpdir/$fileid.c4gh
    crypt4gh decrypt -s $keyfile -f $tmpdir/$fileid.c4gh

    cp $tmpdir/$fileid $outdir/$fileid
    echo "File retrieved and decrypted successfully: $fileid"
done
