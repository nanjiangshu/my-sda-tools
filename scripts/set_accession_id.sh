#!/bin/bash
set -euo pipefail

# Function to generate a safe, random accession ID
# Uses a limited head to prevent hanging on urandom streams

function generate_accession_id {
    local charset='abcdefghjkmnpqrstuvwxyz23456789'
    local p1=$(LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c 6)
    local p2=$(LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c 6)
    echo "aa-File-$p1-$p2"
}

usage="
Usage: $0 [-file-id-list <file_id_list_file>] | [-filepath-list <filepath_list_file> -user <user>]
Options:
  -file-id-list <file_id_list_file>   A file containing a list of file IDs, one per line.
  -filepath-list <filepath_list_file> A file containing a list of file paths, one per line.
  -user <user>                        The user to associate with the accession ID (required if using file paths).
"

# Argument parsing
file_id_list_file=""
filepath_list_file=""
user=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -file-id-list) file_id_list_file="$2"; shift ;;
        -filepath-list) filepath_list_file="$2"; shift ;;
        -user) user="$2"; shift ;;
        *) echo "Unknown parameter: $1"; echo "$usage"; exit 1 ;;
    esac
    shift
done

# Validation
if [[ -n "$file_id_list_file" && -n "$filepath_list_file" ]]; then
    echo "Error: Provide either a file ID list OR a file path list, not both."
    exit 1
fi

if [[ -z "$file_id_list_file" && -z "$filepath_list_file" ]]; then
    echo "Error: Missing input list."
    echo "$usage"
    exit 1
fi

if [[ -n "$filepath_list_file" && -z "$user" ]]; then
    echo "Error: User is required when providing a file path list."
    exit 1
fi

# Set mode and check file existence
is_file_id_mode=false
if [[ -n "$file_id_list_file" ]]; then
    [[ ! -f "$file_id_list_file" ]] && { echo "Error: '$file_id_list_file' not found."; exit 1; }
    listFile="$file_id_list_file"
    is_file_id_mode=true
else
    [[ ! -f "$filepath_list_file" ]] && { echo "Error: '$filepath_list_file' not found."; exit 1; }
    listFile="$filepath_list_file"
fi

# Setup output file
outputFile="$listFile.accession"
echo "Cleaning input list and preparing $outputFile..."

# 1. PRE-PROCESS: Strip trailing/leading whitespace and empty lines from input to a temp file
# This is more efficient than trimming inside the loop.
cleanList=$(mktemp)
sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d' "$listFile" > "$cleanList"

# 2. MAIN LOOP
i=1
num_lines=$(wc -l < "$cleanList")

while read -r entry; do
    accid=$(generate_accession_id)
    
    echo "[$i/$num_lines] Processing: $entry"
    
    if [ "$is_file_id_mode" = true ]; then
        sda-admin file set-accession -fileid "$entry" -accession-id "$accid"
    else
        sda-admin file set-accession -filepath "$entry" -user "$user" -accession-id "$accid"
    fi

    # Append mapping to the accession file
    echo "$entry | $accid" >> "$outputFile"
    
    ((i++))
done < "$cleanList"

# Cleanup
rm "$cleanList"

echo "------------------------------------------------"
echo "Success: $num_lines accession IDs set."
echo "Mappings saved to: $outputFile"
