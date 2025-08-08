#!/bin/bash
set -euo pipefail

# This script retrieves c4gh file by concatenation of the header (from sda.files) and the archived file from the archive and then decrypt it 
s3cmdconf=/data/project-sda/misc/bp-submission/s3cmd-bp-master-archive.conf
binpath=/data/project-sda/my-sda-tools/scripts/
keyfile=c4gh.sec.pem

usage="""
Usage: $0 [OPTIONS] <fileid> 
Options:
  -h, --help        Show this help message and exit
  -s3cmdconf <path> Path to the s3cmd configuration file (default: $s3cmdconf)
  -binpath <path>   Path to the scripts directory (default: $binpath)
  -c4ghkey <path>   Path to the c4gh private key file (default: $keyfile)
"""
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
        *)
            fileid=$1
            shift
            ;;
    esac
done

if [ "$fileid" == "" ];then
    echo "Usage: $0 <fileid>"
    exit 1
fi

if [ ! -f $s3cmdconf ];then
    echo "S3CMD config file not found: $s3cmdconf"
    exit 1
fi

if [ ! -f $binpath/get_header_using_fileid.sh ];then
    echo "Script not found: $binpath/get_header_using_fileid.sh"
    exit 1
fi
if [ ! -f $keyfile ];then
    echo "Private key file not found: $keyfile"
    exit 1
fi


tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT


bash $binpath/get_header_using_fileid.sh $fileid | xxd -r -p > $tmpdir/$fileid.header.bin
s3cmd -c $s3cmdconf get s3://archive-2024-01/$fileid  $tmpdir/$fileid.newstorage
cat $tmpdir/$fileid.header.bin $tmpdir/$fileid.newstorage > $tmpdir/$fileid.c4gh
crypt4gh decrypt -s $keyfile -f $tmpdir/$fileid.c4gh

cp $tmpdir/$fileid $fileid
echo "File retrieved and decrypted successfully: $fileid"
