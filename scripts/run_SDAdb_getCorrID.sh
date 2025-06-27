#!/bin/bash

infile=$1
SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath "$SCRIPT_DIR")

# Check if input file argument is provided
if [ -z "$infile" ]; then
    echo "Usage: $0 file_id_list_file"
    exit 1
fi

while IFS=$'\t' read -r accession_id filepath user; do
    corr_id=$(bash $binpath/SDAdb_GetCorrID.sh $filepath $user $accession_id | awk 'sub(/[ \t\r]+$/, "")')
    if [ -z "$corr_id" ]; then
        echo "No correlation ID found for $accession_id $filepath"
    else
        echo -e "$accession_id\t$corr_id\t$filepath\t$user"
    fi
done < "$infile"