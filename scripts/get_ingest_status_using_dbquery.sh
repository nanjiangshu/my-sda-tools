#!/bin/bash
# this script checks the file status statistics for user files in a given dataset folder using database queries

set -euo pipefail

SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath -- "$SCRIPT_DIR")

usage="Usage: $0 [--overwrite] -u <user> -d <dataset_folder> -o <outdir> [-b <batch_size>] [--verbose]"

user=""
dataset_folder=""
outdir=""
overwrite=false
verbose=false
batch_size=500

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -u)
            user="${2:-}"
            shift 2
            ;;
        -d)
            dataset_folder="${2:-}"
            shift 2
            ;;
        -o)
            outdir="${2:-}"
            shift 2
            ;;
        -b)
            batch_size="${2:-}"
            shift 2
            ;;
        --overwrite)
            overwrite=true
            shift
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        *)
            echo "Unknown option: $key"
            echo "$usage"
            exit 1
            ;;
    esac
done

if [[ -z "$user" || -z "$dataset_folder" || -z "$outdir" ]]; then
    echo "Error: Missing required arguments."
    echo "$usage"
    exit 1
fi

mkdir -p "$outdir"

# Query user files (Runs if --overwrite is set OR output file missing)
if [[ "$overwrite" == "true" || ! -f "$outdir/$dataset_folder.userfiles.txt" ]]; then
    if [[ "$verbose" == "true" ]]; then
        cat << EOF
"$binpath/query_userfiles.sh" "$user" "$dataset_folder" > "$outdir/$dataset_folder.userfiles.txt"
EOF
    fi
    bash "$binpath/query_userfiles.sh" "$user" "$dataset_folder" > "$outdir/$dataset_folder.userfiles.txt"
fi

if [[ ! -s "$outdir/$dataset_folder.userfiles.txt" ]]; then
    echo "No user files found for user: $user in dataset folder: $dataset_folder"
    exit 1
fi

# Extract file IDs
if [[ "$overwrite" == "true" || ! -f "$outdir/$dataset_folder.fileidlist.txt" ]]; then
    if [[ "$verbose" == "true" ]]; then
        cat << EOF
awk -F'|' '{print \$1}' "$outdir/$dataset_folder.userfiles.txt" | sort -u > "$outdir/$dataset_folder.fileidlist.txt"
EOF
    fi
    awk -F'|' '{print $1}' "$outdir/$dataset_folder.userfiles.txt" | sort -u > "$outdir/$dataset_folder.fileidlist.txt"
fi

# Query file event logs
if [[ "$verbose" == "true" ]]; then
    cat << EOF
"$binpath/query_status_in_fileeventlog_with_fileidlist.sh" "$outdir/$dataset_folder.fileidlist.txt" $batch_size > "$outdir/$dataset_folder.status.list.txt"
EOF
fi
bash "$binpath/query_status_in_fileeventlog_with_fileidlist.sh" "$outdir/$dataset_folder.fileidlist.txt" "$batch_size" > "$outdir/$dataset_folder.status.list.txt"

# Output summary statistics
if [[ "$verbose" == "true" ]]; then
    cat << EOF
awk -F'|' '{print \$2}' "$outdir/$dataset_folder.status.list.txt" | awk -F, '{print \$1}' | sort | uniq -c
EOF
fi
awk -F'|' '{print $2}' "$outdir/$dataset_folder.status.list.txt" | awk -F, '{print $1}' | sort | uniq -c