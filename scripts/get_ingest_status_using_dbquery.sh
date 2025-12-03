#!/bin/bash
# this script checks the file status statistics for user files in a given dataset folder using database queries

set -euo pipefail

SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath -- "$SCRIPT_DIR") # Added -- for robustness

usage="""
Usage: $0 [--overwrite] -u <user> -d <dataset_folder> -o <outdir>
-u <user>           : the LSAAI user ID
-d <dataset_folder> : the dataset folder name
-o <outdir>         : directory to save intermediate and final results
-b <batch_size>    : (optional) number of file IDs to process per batch (default: 500)
--overwrite         : (optional) overwrite existing files in the output directory except for the final status list file
"""

user=
dataset_folder=
outdir=
overwrite=false
batch_size=500
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -u)
            user="$2"
            shift
            shift
            ;;
        -d)
            dataset_folder="$2"
            shift
            shift
            ;;
        -o)
            outdir="$2"
            shift
            shift
            ;;
        -b)
            batch_size="$2"
            shift
            shift
            ;;
        --overwrite)
            overwrite=true
            shift
            ;;
        *)
            echo "Unknown option: $key"
            echo "$usage"
            exit 1
            ;;
    esac
done

if [ -z "$user" ] || [ -z "$dataset_folder" ] || [ -z "$outdir" ]; then
    echo "Error: Missing required arguments."
    echo "$usage"
    exit 1
fi

if [ ! -d "$outdir" ]; then
    mkdir -p "$outdir"
fi

if [[ "$overwrite" == "false" || ! -f "$outdir/$dataset_folder.userfiles.txt" ]]; then
    bash "$binpath/query_userfiles.sh" "$user" "$dataset_folder" > "$outdir/$dataset_folder.userfiles.txt"
fi

if [ ! -s "$outdir/$dataset_folder.userfiles.txt" ]; then
    echo "No user files found for user: $user in dataset folder: $dataset_folder"
    exit 1
fi

# Variables quoted, clearer awk -F
if [[ "$overwrite" == "false" || ! -f "$outdir/$dataset_folder.fileidlist.txt" ]]; then
    awk -F'|' '{print $1}' "$outdir/$dataset_folder.userfiles.txt" | sort -u > "$outdir/$dataset_folder.fileidlist.txt"
fi

# Variables quoted
bash "$binpath/query_status_in_fileeventlog_with_fileidlist.sh" "$outdir/$dataset_folder.fileidlist.txt" $batch_size > "$outdir/$dataset_folder.status.list.txt"

# Variables quoted, clearer awk -F
awk -F'|' '{print $2}' "$outdir/$dataset_folder.status.list.txt" | awk -F, '{print $1}' | sort | uniq -c
