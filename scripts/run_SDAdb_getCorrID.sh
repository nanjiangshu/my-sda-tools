#!/bin/bash

infile=$1
SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath "$SCRIPT_DIR/..")

# Check if input file argument is provided
if [ -z "$infile" ]; then
    echo "Usage: $0 file_id_list_file"
    exit 1
fi

while IFS=$'\t' read -r accession_id filepath user; do
    bash $binpath/SDAdb_GetCorrID.sh $filepath $user $accession_id
done < "$infile"