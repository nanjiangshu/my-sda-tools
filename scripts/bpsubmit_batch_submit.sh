#!/usr/bin/env bash

set -uo pipefail

# ------------------------------------------------------------------------------
# Usage / Help Function
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 LIST_FILE"
    echo ""
    echo "  LIST_FILE  File with one dataset per line, '|' delimited:"
    echo "             DATASET_FOLDER|MAIL_UPLOADER|MAIL_UPLOADER_NAME"
    echo ""
    echo "  Empty lines and lines starting with '#' are ignored."
    echo "  Each dataset is submitted with bpsubmit_submit.sh inside ./DATASET_FOLDER"
    echo "  (created if missing) and its output is logged to"
    echo "  ./DATASET_FOLDER/bpsubmit_submit.log"
    echo ""
    echo "Example LIST_FILE:"
    echo "  DATASET_AAAAAAA|aaaaaaaaa.aaaaaa@dummy.com|Dummy User"
    exit 1
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

LIST_FILE="$1"
if [[ ! -f "$LIST_FILE" ]]; then
    echo "[-] Error: List file '$LIST_FILE' not found." >&2
    exit 1
fi

# Absolute path, since each submission runs after cd into the dataset folder
SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
SUBMIT_SCRIPT="${SCRIPT_PATH}/bpsubmit_submit.sh"
if [[ ! -f "$SUBMIT_SCRIPT" ]]; then
    echo "[-] Error: Script not found: $SUBMIT_SCRIPT" >&2
    exit 1
fi

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

WORK_DIR="$PWD"
SUCCEEDED=()
FAILED=()

# ------------------------------------------------------------------------------
# Process Each Dataset
# ------------------------------------------------------------------------------
# Read from fd 3 so that commands inside the loop cannot consume the list file
line_no=0
while IFS='|' read -r DATASET_FOLDER MAIL_UPLOADER MAIL_UPLOADER_NAME _ <&3 || [[ -n "${DATASET_FOLDER:-}" ]]; do
    line_no=$((line_no + 1))
    DATASET_FOLDER=$(trim "${DATASET_FOLDER:-}")
    MAIL_UPLOADER=$(trim "${MAIL_UPLOADER:-}")
    MAIL_UPLOADER_NAME=$(trim "${MAIL_UPLOADER_NAME:-}")

    # Skip empty and comment lines
    if [[ -z "$DATASET_FOLDER" || "$DATASET_FOLDER" == \#* ]]; then
        DATASET_FOLDER=""
        continue
    fi

    if [[ -z "$MAIL_UPLOADER" || -z "$MAIL_UPLOADER_NAME" ]]; then
        echo "[-] Line ${line_no}: missing MAIL_UPLOADER or MAIL_UPLOADER_NAME for '${DATASET_FOLDER}'. Skipping." >&2
        FAILED+=("${DATASET_FOLDER} (line ${line_no}: malformed row)")
        DATASET_FOLDER=""
        continue
    fi

    echo "=========================================================================="
    echo " [batch] Submitting ${DATASET_FOLDER} (${MAIL_UPLOADER_NAME} <${MAIL_UPLOADER}>)"
    echo "=========================================================================="

    mkdir -p "${WORK_DIR}/${DATASET_FOLDER}"
    LOG_FILE="${WORK_DIR}/${DATASET_FOLDER}/bpsubmit_submit.log"

    # Run in a subshell so that cd and failures do not affect the batch loop
    (
        cd "${WORK_DIR}/${DATASET_FOLDER}" &&
        bash "$SUBMIT_SCRIPT" -d "$DATASET_FOLDER" -n "$MAIL_UPLOADER_NAME" -m "$MAIL_UPLOADER"
    ) < /dev/null 2>&1 | tee "$LOG_FILE"
    rc=${PIPESTATUS[0]}

    if [[ $rc -eq 0 ]]; then
        echo "[+] ${DATASET_FOLDER}: submitted successfully."
        SUCCEEDED+=("${DATASET_FOLDER}")
    else
        echo "[-] ${DATASET_FOLDER}: submission FAILED (exit code ${rc}). See ${LOG_FILE}" >&2
        FAILED+=("${DATASET_FOLDER} (exit code ${rc}, log: ${LOG_FILE})")
    fi
    DATASET_FOLDER=""
done 3< "$LIST_FILE"

# ------------------------------------------------------------------------------
# Summary Report
# ------------------------------------------------------------------------------
echo ""
echo "=========================================================================="
echo " Batch submission summary"
echo "=========================================================================="
echo "Succeeded (${#SUCCEEDED[@]}):"
for ds in ${SUCCEEDED[@]+"${SUCCEEDED[@]}"}; do
    echo "    + $ds"
done
echo "Failed (${#FAILED[@]}):"
for ds in ${FAILED[@]+"${FAILED[@]}"}; do
    echo "    - $ds"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
fi
