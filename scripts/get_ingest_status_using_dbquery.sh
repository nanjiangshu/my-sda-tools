#!/bin/bash
# this script checks the file status statistics for user files in a given dataset folder using database queries

set -euo pipefail

SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath -- "$SCRIPT_DIR")

usage="Usage: $0 [--overwrite] -u <user> -d <dataset_folder> -o <outdir> [-b <batch_size>] [--verbose] [-t|--time]"

user=""
dataset_folder=""
outdir=""
overwrite=false
verbose=false
show_time=false
batch_size=500

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -u)
            [[ $# -lt 2 ]] && { echo "Error: Option -u requires an argument."; echo "$usage"; exit 1; }
            user="$2"
            shift 2
            ;;
        -d)
            [[ $# -lt 2 ]] && { echo "Error: Option -d requires an argument."; echo "$usage"; exit 1; }
            dataset_folder="$2"
            shift 2
            ;;
        -o)
            [[ $# -lt 2 ]] && { echo "Error: Option -o requires an argument."; echo "$usage"; exit 1; }
            outdir="$2"
            shift 2
            ;;
        -b)
            [[ $# -lt 2 ]] && { echo "Error: Option -b requires an argument."; echo "$usage"; exit 1; }
            batch_size="$2"
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
        -t|--time)
            show_time=true
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

# Sanitize dataset_folder for use in filenames (replaces '/' with '_')
dataset_stem=$(echo "$dataset_folder" | tr '/' '_')

userfiles_file="$outdir/$dataset_stem.userfiles.txt"
fileidlist_file="$outdir/$dataset_stem.fileidlist.txt"
statuslist_file="$outdir/$dataset_stem.status.list.txt"

# Helper function to execute and conditionally time commands
run_script() {
    local label="$1"
    shift
    if [[ "$show_time" == "true" ]]; then
        echo "=== Running $label ===" >&2
        # Use a subshell to redirect time's output to stderr
        ( time "$@" )
    else
        "$@"
    fi
}

# Query user files (Runs if --overwrite is set OR output file missing)
if [[ "$overwrite" == "true" || ! -f "$userfiles_file" ]]; then
    if [[ "$verbose" == "true" ]]; then
        cat << EOF
"$binpath/query_userfiles.sh" "$user" "$dataset_folder" > "$userfiles_file"
EOF
    fi
    run_script "query_userfiles.sh" bash "$binpath/query_userfiles.sh" "$user" "$dataset_folder" > "$userfiles_file"
fi

if [[ ! -s "$userfiles_file" ]]; then
    echo "No user files found for user: $user in dataset folder: $dataset_folder"
    exit 1
fi

# Extract file IDs
if [[ "$overwrite" == "true" || ! -f "$fileidlist_file" ]]; then
    if [[ "$verbose" == "true" ]]; then
        cat << EOF
awk -F'|' '{print \$1}' "$userfiles_file" | sort -u > "$fileidlist_file"
EOF
    fi
    awk -F'|' '{print $1}' "$userfiles_file" | sort -u > "$fileidlist_file"
fi

# Query file event logs
if [[ "$verbose" == "true" ]]; then
    cat << EOF
"$binpath/query_status_in_fileeventlog_with_fileidlist.sh" "$fileidlist_file" $batch_size > "$statuslist_file"
EOF
fi
run_script "query_status_in_fileeventlog_with_fileidlist.sh" bash "$binpath/query_status_in_fileeventlog_with_fileidlist.sh" "$fileidlist_file" "$batch_size" > "$statuslist_file"

# Output summary statistics
if [[ "$verbose" == "true" ]]; then
    cat << EOF
awk -F'|' '{print \$2}' "$statuslist_file" | awk -F, '{print \$1}' | sort | uniq -c
EOF
fi
awk -F'|' '{print $2}' "$statuslist_file" | awk -F, '{print $1}' | sort | uniq -c