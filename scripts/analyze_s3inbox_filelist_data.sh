#!/usr/bin/env bash

# Analyze S3 inbox file list data to extract dataset directories, their min/max dates, and sizes
# Input files should contain S3 paths with dates in the format YYYY-MM-DD as the first field.
# Output columns: human-readable size, min date, max date, directory path, number of files
# (NUMBER_FILES is last so that tools reading the first four columns are not affected)
# Example usage:
#   ./analyze_s3inbox_filelist_data.sh -older-than 30 input_file.txt
# The input file should have lines like:
# YYYY-MM-DD s3://bucket/path/to/DATASET_xxx/file
# The script will output lines like:
# 1.2K 2024-01-01 2024-01-31 <userid>/DATASET_xxx 42
# The raw bytes column is zero-padded to maintain sorting order.
# The script requires s3cmd to be installed and configured with the appropriate S3 credentials.
# The script will create temporary files for intermediate data and clean them up on exit.
# The script supports an optional -older-than argument to filter datasets by their max date.
# The script assumes that the S3 paths follow the pattern s3://bucket/path/to/DATASET_xxx/file with the date as the first field.
# The bucket in each path is kept: the same dataset can exist in two buckets (inbox and
# inbox-2024-01) and size and number of files are always read from the bucket of the listing.
# If the input files contain two buckets, a dataset in both gets one row per bucket.

set -euo pipefail

S3_CONFIG="$HOME/.sda/s3cmd-bp-master-inbox.conf"

usage() {
    echo "Usage: $0 [-older-than DAYS] <input_file1> [input_file2 ...]" >&2
    echo "  -older-than DAYS  Show only datasets whose MAX_DATE is older than DAYS days" >&2
    exit 1
}

# Parse options
OLDER_THAN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -older-than|--older-than)
            [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]] && { echo "Error: -older-than requires a non-negative integer." >&2; usage; }
            OLDER_THAN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Usage check
if [[ $# -lt 1 ]]; then
    usage
fi

# Cutoff date (YYYY-MM-DD) for -older-than; supports GNU and BSD/macOS date
CUTOFF_DATE=""
if [[ -n "$OLDER_THAN" ]]; then
    CUTOFF_DATE=$(date -d "-${OLDER_THAN} days" +%Y-%m-%d 2>/dev/null || date -v-"${OLDER_THAN}"d +%Y-%m-%d)
fi

# Verify input files exist
for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Input file '$file' not found." >&2
        exit 1
    fi
done

# Temporary files for intermediate data
TMP_IDS=$(mktemp)
TMP_DATES=$(mktemp)
TMP_SIZES=$(mktemp)
TMP_FINAL=$(mktemp)
TMP_CONF=$(mktemp)

cleanup() {
    rm -f "$TMP_IDS" "$TMP_DATES" "$TMP_SIZES" "$TMP_FINAL" "$TMP_CONF"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 1. Extract min and max dates per directory across all specified input files
# -----------------------------------------------------------------------------
awk '
    # Portable match (BSD/macOS awk has no 3-arg match and chokes on "/" in
    # regex literals), so use a string regex and strip the bucket with sub()
    match($0, "s3://[^/]+/[^/]+/DATASET_[^/]+") {
        dir = substr($0, RSTART, RLENGTH)
        sub("^s3://", "", dir)
        bucket = dir
        sub("/.*", "", bucket)
        sub("^[^/]+/", "", dir)
        key = bucket "\t" dir
        date = $1  # First field is YYYY-MM-DD
        if (!(key in min_date) || date < min_date[key]) {
            min_date[key] = date
        }
        if (!(key in max_date) || date > max_date[key]) {
            max_date[key] = date
        }
    }
    END {
        for (k in min_date) {
            print k "\t" min_date[k] "\t" max_date[k]
        }
    }
' "$@" > "$TMP_DATES"

# Keep only directories whose max date is older than the cutoff
if [[ -n "$CUTOFF_DATE" ]]; then
    awk -F'\t' -v cutoff="$CUTOFF_DATE" '$4 < cutoff' "$TMP_DATES" > "$TMP_FINAL"
    mv "$TMP_FINAL" "$TMP_DATES"
fi

# Extract unique directory paths
cut -f1,2 "$TMP_DATES" > "$TMP_IDS"

# -----------------------------------------------------------------------------
# 2. Run s3cmd du for each directory and parse size in bytes
# -----------------------------------------------------------------------------
# The config may set human_readable_sizes = True, which makes du print e.g. "758G"
# instead of bytes; use a temporary copy of the config with it switched off.
grep -viE '^[[:space:]]*human_readable_sizes[[:space:]]*=' "$S3_CONFIG" > "$TMP_CONF"
echo "human_readable_sizes = False" >> "$TMP_CONF"

while IFS=$'\t' read -r bucket dir; do
    [[ -z "$dir" ]] && continue

    # du prints "<bytes> <N> objects s3://..."; take the size and the number of files
    # of the bucket where the dataset was listed (not of another bucket with the same dataset).
    # The trailing slash keeps DATASET_X from also counting DATASET_X2 (du matches a prefix).
    du_output=$(s3cmd -c "$TMP_CONF" du "s3://$bucket/$dir/" 2>/dev/null || true)
    bytes=$(echo "$du_output" | awk '{print $1}' | grep -E '^[0-9]+$' | head -n1 || echo "")
    nfiles=$(echo "$du_output" | awk 'NR==1 && $2 ~ /^[0-9]+$/ {print $2}')

    printf "%s\t%s\t%s\t%s\n" "$bucket" "$dir" "${bytes:-0}" "${nfiles:-0}"
done < "$TMP_IDS" > "$TMP_SIZES"

# -----------------------------------------------------------------------------
# 3. Combine size and dates, convert bytes to human-readable format, and sort
# -----------------------------------------------------------------------------
awk -F'\t' '
    function hr(b,   units, u, size) {
        split("B K M G T P", units, " ")
        u = 1
        size = b
        while (size >= 1024 && u < 6) {
            size /= 1024
            u++
        }
        if (u == 1) return sprintf("%dB", size)
        else if (size == int(size)) return sprintf("%d%s", size, units[u])
        else return sprintf("%.1f%s", size, units[u])
    }

    FILENAME == ARGV[1] {
        min_date[$1 "\t" $2] = $3
        max_date[$1 "\t" $2] = $4
        next
    }
    {
        key = $1 "\t" $2
        dir = $2
        bytes = $3
        nfiles = $4
        human_size = hr(bytes)
        d1 = min_date[key] ? min_date[key] : "N/A"
        d2 = max_date[key] ? max_date[key] : "N/A"

        # Output zero-padded raw bytes as 1st field for numerical sorting
        printf "%020d\t%s %s %s %s %d\n", bytes, human_size, d1, d2, dir, nfiles
    }
' "$TMP_DATES" "$TMP_SIZES" > "$TMP_FINAL"

# Sort descending by numeric bytes and print final output
if [[ -n "$CUTOFF_DATE" ]]; then
    echo "# Only datasets with last modified (MAX_DATE) before $CUTOFF_DATE (older than $OLDER_THAN days) are listed"
fi
echo "SIZE MIN_DATE MAX_DATE DIR NUMBER_FILES"
sort -r "$TMP_FINAL" | cut -f2-
