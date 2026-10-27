#!/usr/bin/env bash

# Delete the datasets annotated "to_be_deleted" in an output_inbox*.txt file from an S3 inbox bucket.
# Input rows look like:
#   SIZE MIN_DATE MAX_DATE <userid>_lifescience-ri.eu/DATASET_xxx  "dropped" "to_be_deleted"
# Each matching row is deleted with: s3cmd del --recursive s3://<bucket>/<userid>_lifescience-ri.eu/DATASET_xxx/
#
# Safe by default: without --execute the script only prints the commands (and what
# s3cmd would remove, via its own --dry-run). With --execute it lists the datasets and
# asks for confirmation before deleting anything. Deletion cannot be undone.
#
# Example:
#   ./delete_s3inbox_datasets.sh -b inbox-2024-01 output_inbox-2024-01.txt            # dry run
#   ./delete_s3inbox_datasets.sh -b inbox-2024-01 --execute output_inbox-2024-01.txt  # really delete
#   ./delete_s3inbox_datasets.sh -b inbox output_inbox_older_than_60.txt

set -euo pipefail

S3_CONFIG="$HOME/.sda/s3cmd-bp-master-inbox.conf"
TAG="to_be_deleted"

usage() {
    echo "Usage: $0 -b BUCKET [--execute] [-t TAG] <input_file1> [input_file2 ...]" >&2
    echo "  -b BUCKET   S3 bucket the datasets are in, e.g. inbox or inbox-2024-01 (Mandatory)" >&2
    echo "  -t TAG      Annotation selecting the rows to delete (default: $TAG)" >&2
    echo "  --execute   Really delete (default: dry run, nothing is deleted)" >&2
    exit 1
}

BUCKET=""
EXECUTE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b) [[ $# -lt 2 ]] && usage; BUCKET="$2"; shift 2 ;;
        -t) [[ $# -lt 2 ]] && usage; TAG="$2"; shift 2 ;;
        --execute) EXECUTE=true; shift ;;
        -h|--help) usage ;;
        -*) echo "Error: Unknown option '$1'." >&2; usage ;;
        *) break ;;
    esac
done

[[ -z "$BUCKET" ]] && { echo "Error: -b BUCKET is required." >&2; usage; }
[[ $# -lt 1 ]] && { echo "Error: no input file given (e.g. output_inbox.txt)." >&2; usage; }
for f in "$@"; do
    [[ -f "$f" ]] || { echo "Error: Input file '$f' not found." >&2; exit 1; }
done

# Dataset directories (<userid>_lifescience-ri.eu/DATASET_xxx) of rows carrying the tag
DIRS=$(awk -v tag="\"$TAG\"" '
    $4 ~ /^[^\/]+\/DATASET_[^\/]+$/ {
        for (i = 5; i <= NF; i++) if ($i == tag) { print $4; break }
    }' "$@" | sort -u)

if [[ -z "$DIRS" ]]; then
    echo "No datasets annotated \"$TAG\" found."
    exit 0
fi

COUNT=$(echo "$DIRS" | wc -l | tr -d ' ')
echo "Bucket: s3://$BUCKET/   Datasets annotated \"$TAG\": $COUNT"
echo "$DIRS" | sed "s|^|  s3://$BUCKET/|"
echo

if ! $EXECUTE; then
    echo "# DRY RUN: nothing is deleted. Commands that --execute would run:"
    while IFS= read -r dir; do
        # Trailing slash so DATASET_ABC does not also match DATASET_ABCDEF
        echo "s3cmd -c $S3_CONFIG del --recursive s3://$BUCKET/$dir/"
    done <<< "$DIRS"
    exit 0
fi

read -r -p "Permanently delete these $COUNT datasets from s3://$BUCKET/ ? Type the bucket name to confirm: " answer
[[ "$answer" == "$BUCKET" ]] || { echo "Aborted."; exit 1; }

LOG="delete_s3inbox_datasets.$(date +%Y%m%d_%H%M%S).log"
echo "Logging to $LOG"

# Refuse anything that is not exactly <userid>_lifescience-ri.eu/DATASET_xxx, so an empty
# or truncated path can never turn into a bucket-wide recursive delete
safe_dir() {
    [[ "$1" =~ ^[^/]+/DATASET_[^/]+$ ]]
}

FAILED=0
SKIPPED=0
while IFS= read -r dir; do
    if ! safe_dir "$dir"; then
        echo "SKIPPED (unexpected path format): '$dir'" | tee -a "$LOG" >&2
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    target="s3://$BUCKET/$dir/"

    # s3cmd exits 0 and deletes nothing for a missing prefix; check what is really there
    du_out=$(s3cmd -c "$S3_CONFIG" du "$target" 2>/dev/null || true)
    objects=$(echo "$du_out" | awk '{print $2}' | head -n1)
    if [[ -z "$objects" || "$objects" == "0" ]]; then
        echo "SKIPPED (nothing found under $target)" | tee -a "$LOG"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo ">>> Deleting $target ($objects objects)" | tee -a "$LOG"
    if ! s3cmd -c "$S3_CONFIG" del --recursive "$target" 2>&1 | tee -a "$LOG"; then
        echo "FAILED: $dir" | tee -a "$LOG" >&2
        FAILED=$((FAILED + 1))
    fi
done <<< "$DIRS"

echo "Done. $((COUNT - FAILED - SKIPPED)) deleted, $SKIPPED skipped, $FAILED failed. Log: $LOG"
[[ $FAILED -eq 0 ]]
