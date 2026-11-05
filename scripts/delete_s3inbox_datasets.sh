#!/usr/bin/env bash

# Delete the datasets annotated "to_be_deleted" in an output_inbox*.txt file from the S3 inbox.
# Input rows look like:
#   SIZE MIN_DATE MAX_DATE <userid>_lifescience-ri.eu/DATASET_xxx  "dropped" "to_be_deleted"
#
# By default each matching row is deleted through the API with
# delete_inboxfiles_to_datasetfolder.sh (-u <userid>@lifescience-ri.eu -d DATASET_xxx).
# With --s3cmd it is deleted instead with:
#   s3cmd del --recursive s3://<bucket>/<userid>_lifescience-ri.eu/DATASET_xxx/
#
# Safe by default: without --execute the script only shows what would be deleted
# (API mode: the dry-run of delete_inboxfiles_to_datasetfolder.sh; s3cmd mode: the commands).
# With --execute it lists the datasets and asks for confirmation before deleting anything.
# Deletion cannot be undone.
#
# Example:
#   ./delete_s3inbox_datasets.sh output_inbox-2024-01.txt                       # API, dry run
#   ./delete_s3inbox_datasets.sh --execute output_inbox-2024-01.txt             # API, really delete
#   ./delete_s3inbox_datasets.sh -T bp-staging --execute output_inbox.txt       # API, staging
#   ./delete_s3inbox_datasets.sh --s3cmd -b inbox-2024-01 output_inbox-2024-01.txt            # s3cmd, dry run
#   ./delete_s3inbox_datasets.sh --s3cmd -b inbox-2024-01 --execute output_inbox-2024-01.txt  # s3cmd, delete

set -euo pipefail

S3_CONFIG="$HOME/.sda/s3cmd-bp-master-inbox.conf"
TAG="to_be_deleted"
TARGET="bp-prod"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
API_DELETE_SCRIPT="$SCRIPT_DIR/delete_inboxfiles_to_datasetfolder.sh"

usage() {
    echo "Usage: $0 [--s3cmd -b BUCKET] [--execute] [-T TARGET] [-p API_HOST] [-t TAG] <input_file1> [input_file2 ...]" >&2
    echo "  --s3cmd     Delete with s3cmd instead of the API (default: API via delete_inboxfiles_to_datasetfolder.sh)" >&2
    echo "  -b BUCKET   S3 bucket the datasets are in, e.g. inbox or inbox-2024-01 (Mandatory with --s3cmd)" >&2
    echo "  -T TARGET   API target: bp-prod or bp-staging (default: $TARGET; API mode only)" >&2
    echo "  -p API_HOST API host URL overriding the target's default (API mode only)" >&2
    echo "  -t TAG      Annotation selecting the rows to delete (default: $TAG)" >&2
    echo "  --execute   Really delete (default: dry run, nothing is deleted)" >&2
    exit 1
}

BUCKET=""
EXECUTE=false
USE_S3CMD=false
API_HOST_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b) [[ $# -lt 2 ]] && usage; BUCKET="$2"; shift 2 ;;
        -t) [[ $# -lt 2 ]] && usage; TAG="$2"; shift 2 ;;
        -T) [[ $# -lt 2 ]] && usage; TARGET="$2"; shift 2 ;;
        -p) [[ $# -lt 2 ]] && usage; API_HOST_OVERRIDE="$2"; shift 2 ;;
        --s3cmd) USE_S3CMD=true; shift ;;
        --execute) EXECUTE=true; shift ;;
        -h|--help) usage ;;
        -*) echo "Error: Unknown option '$1'." >&2; usage ;;
        *) break ;;
    esac
done

if $USE_S3CMD; then
    [[ -z "$BUCKET" ]] && { echo "Error: -b BUCKET is required with --s3cmd." >&2; usage; }
else
    [[ -x "$API_DELETE_SCRIPT" || -f "$API_DELETE_SCRIPT" ]] \
        || { echo "Error: $API_DELETE_SCRIPT not found." >&2; exit 1; }
fi
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
if $USE_S3CMD; then
    echo "Method: s3cmd   Bucket: s3://$BUCKET/   Datasets annotated \"$TAG\": $COUNT"
    echo "$DIRS" | sed "s|^|  s3://$BUCKET/|"
    CONFIRM_WORD="$BUCKET"
    CONFIRM_WHERE="s3://$BUCKET/"
else
    echo "Method: API ($(basename "$API_DELETE_SCRIPT"))   Target: $TARGET   Datasets annotated \"$TAG\": $COUNT"
    echo "$DIRS" | sed "s|^|  |"
    CONFIRM_WORD="$TARGET"
    CONFIRM_WHERE="target $TARGET"
fi
echo

# Refuse anything that is not exactly <userid>_lifescience-ri.eu/DATASET_xxx, so an empty
# or truncated path can never turn into a bucket-wide recursive delete
safe_dir() {
    [[ "$1" =~ ^[^/]+/DATASET_[^/]+$ ]]
}

# Run delete_inboxfiles_to_datasetfolder.sh for one "<userid>_lifescience-ri.eu/DATASET_xxx".
# Extra arguments (e.g. -n for dry run) are passed through.
api_delete() {
    local dir="$1"; shift
    local user="${dir%%/*}" folder="${dir#*/}"
    user="${user/_lifescience-ri.eu/@lifescience-ri.eu}"
    # Always pass -y: the confirmation was already given here, so the child must never prompt
    local args=(-d "$folder" -u "$user" -t "$TARGET" -y)
    [[ -n "$API_HOST_OVERRIDE" ]] && args+=(-p "$API_HOST_OVERRIDE")
    bash "$API_DELETE_SCRIPT" "${args[@]}" "$@" </dev/null
}

if ! $EXECUTE; then
    if $USE_S3CMD; then
        echo "# DRY RUN: nothing is deleted. Commands that --execute would run:"
        while IFS= read -r dir; do
            # Trailing slash so DATASET_ABC does not also match DATASET_ABCDEF
            echo "s3cmd -c $S3_CONFIG del --recursive s3://$BUCKET/$dir/"
        done <<< "$DIRS"
    else
        echo "# DRY RUN: nothing is deleted. Dry-run of each dataset:"
        while IFS= read -r dir; do
            safe_dir "$dir" || { echo "SKIPPED (unexpected path format): '$dir'" >&2; continue; }
            echo ">>> $dir"
            api_delete "$dir" -n || echo "FAILED (dry run): $dir" >&2
        done <<< "$DIRS"
    fi
    exit 0
fi

read -r -p "Permanently delete these $COUNT datasets from $CONFIRM_WHERE ? Type '$CONFIRM_WORD' to confirm: " answer
[[ "$answer" == "$CONFIRM_WORD" ]] || { echo "Aborted."; exit 1; }

LOG="delete_s3inbox_datasets.$(date +%Y%m%d_%H%M%S).log"
echo "Logging to $LOG"

FAILED=0
SKIPPED=0
while IFS= read -r dir; do
    if ! safe_dir "$dir"; then
        echo "SKIPPED (unexpected path format): '$dir'" | tee -a "$LOG" >&2
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if $USE_S3CMD; then
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
    else
        echo ">>> Deleting $dir via API" | tee -a "$LOG"
        # pipefail makes the pipeline fail when the child script fails.
        if ! api_delete "$dir" 2>&1 | tee -a "$LOG"; then
            echo "FAILED: $dir" | tee -a "$LOG" >&2
            FAILED=$((FAILED + 1))
        fi
    fi
done <<< "$DIRS"

echo "Done. $((COUNT - FAILED - SKIPPED)) deleted, $SKIPPED skipped, $FAILED failed. Log: $LOG"
[[ $FAILED -eq 0 ]]
