#!/usr/bin/env bash

# This script deletes files from S3Inbox for a specified dataset folder for a given user.
# It supports a dry-run mode to list files that would be deleted without actually deleting them.
set -euo pipefail

# ------------------------------------------------------------------------------
# Usage / Help
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -d DATASET_FOLDER -u USER_ID [-n] [-h] [-p API_HOST]"
    echo "  -d  Dataset folder name (Mandatory)"
    echo "  -u  User ID / Username, e.g. user@lifescience-ri.eu (Mandatory)"
    echo "  -n  Dry-run mode (Only list files that would be deleted, do not delete)"
    echo "  -p  API host URL (Optional, default: https://api.bp.nbis.se)"
    echo "  -h  Show this help message"
    exit 1
}

API_HOST="https://api.bp.nbis.se"
ACCESS_TOKEN=$(grep access_token ~/.sda/s3cmd-bp-download.conf 2>/dev/null | awk '{print $NF}' || true)

DATASET_FOLDER=""
USER_ID=""
DRY_RUN=false

while getopts ":d:u:p:nh" opt; do
    case "${opt}" in
        d) DATASET_FOLDER="${OPTARG}" ;;
        u) USER_ID="${OPTARG}" ;;
        p) API_HOST="${OPTARG}" ;;
        n) DRY_RUN=true ;;
        h) usage ;;
        :)
            echo "[-] Error: Option -${OPTARG} requires an argument." >&2
            usage
            ;;
        \?)
            echo "[-] Error: Invalid option -${OPTARG}." >&2
            usage
            ;;
    esac
done

if [[ -z "$DATASET_FOLDER" || -z "$USER_ID" ]]; then
    echo "[-] Error: -d DATASET_FOLDER and -u USER_ID are mandatory." >&2
    usage
fi

# The API matches path_prefix as a plain string prefix, so "DS1" would also match "DS10/...".
# Always query with a trailing slash so only files inside the folder itself are selected.
DATASET_FOLDER="${DATASET_FOLDER%/}"
if [[ -z "$DATASET_FOLDER" ]]; then
    echo "[-] Error: DATASET_FOLDER must not be empty or '/'." >&2
    exit 1
fi
PATH_PREFIX="${DATASET_FOLDER}/"
API_HOST="${API_HOST%/}"

# Verify required tools
REQUIRED_TOOLS=("curl" "jq")
MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "[-] Error: Missing required dependencies: ${MISSING_TOOLS[*]}" >&2
    echo "    Please install missing tools (e.g., sudo apt install jq curl)." >&2
    exit 1
fi

if [[ -z "${ACCESS_TOKEN:-}" ]]; then
    echo "[-] Error: \$ACCESS_TOKEN could not be extracted from ~/.sda/s3cmd-bp-download.conf." >&2
    exit 1
fi

echo "=========================================================================="
echo " Dataset Deletion Tool"
echo " Dataset Folder : ${DATASET_FOLDER}"
echo " User ID        : ${USER_ID}"
echo " API Host       : ${API_HOST}"
echo " Mode           : $( [ "$DRY_RUN" = true ] && echo "DRY-RUN (No files will be deleted)" || echo "LIVE DELETE" )"
echo "=========================================================================="

# ------------------------------------------------------------------------------
# 1. Cursor-Based Paginated Fetch of File List via API
# ------------------------------------------------------------------------------
echo "[+] Querying all pages for path prefix '${PATH_PREFIX}' using cursor pagination..."

ALL_FILES_TMP=$(mktemp)
HEADERS_TMP=$(mktemp)
BODY_TMP=$(mktemp)

trap 'rm -f "$ALL_FILES_TMP" "$HEADERS_TMP" "$BODY_TMP"' EXIT

CURSOR=""
PAGE=1
LIMIT=10000
USER_ID_ENC=$(jq -rn --arg v "$USER_ID" '$v|@uri')
PATH_PREFIX_ENC=$(jq -rn --arg v "$PATH_PREFIX" '$v|@uri')

while true; do
    # Build URL with path_prefix, limit, and cursor if present
    REQ_URL="${API_HOST}/users/${USER_ID_ENC}/files?path_prefix=${PATH_PREFIX_ENC}&limit=${LIMIT}"
    if [[ -n "$CURSOR" ]]; then
        REQ_URL="${REQ_URL}&cursor=$(jq -rn --arg v "$CURSOR" '$v|@uri')"
    fi

    # Execute request dumping headers to $HEADERS_TMP and body to $BODY_TMP
    HTTP_STATUS=$(curl -s -D "$HEADERS_TMP" -o "$BODY_TMP" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -X GET "$REQ_URL" \
        -w "%{http_code}" || true)

    if [[ "$HTTP_STATUS" != "200" ]]; then
        echo "[-] Error: API call failed on page $PAGE with HTTP status $HTTP_STATUS" >&2
        cat "$BODY_TMP" >&2
        echo "" >&2
        exit 1
    fi

    # A non-array body means something went wrong; do not treat it as "no more files"
    if ! jq -e 'type == "array"' "$BODY_TMP" >/dev/null 2>&1; then
        echo "[-] Error: Unexpected (non JSON array) response on page $PAGE:" >&2
        cat "$BODY_TMP" >&2
        echo "" >&2
        exit 1
    fi

    PAGE_COUNT=$(jq 'length' "$BODY_TMP")
    if [[ "$PAGE_COUNT" -eq 0 ]]; then
        break
    fi
    echo "    Fetched page ${PAGE} (${PAGE_COUNT} items)..."

    # Store one "fileID<TAB>fileStatus<TAB>inboxPath" line per file inside the dataset folder
    jq -r --arg p "$PATH_PREFIX" \
        '.[] | select((.inboxPath // "") | startswith($p)) | [.fileID // "", .fileStatus // "", .inboxPath] | @tsv' \
        "$BODY_TMP" >> "$ALL_FILES_TMP"

    # Extract X-Next-Cursor from headers file (case-insensitive grep)
    NEXT_CURSOR=$(grep -i '^x-next-cursor:' "$HEADERS_TMP" | awk '{print $2}' | tr -d '\r\n' || true)

    # Stop if no next cursor is present or if cursor does not advance
    if [[ -z "$NEXT_CURSOR" || "$NEXT_CURSOR" == "$CURSOR" ]]; then
        break
    fi

    CURSOR="$NEXT_CURSOR"
    PAGE=$((PAGE + 1))
done

if [[ ! -s "$ALL_FILES_TMP" ]]; then
    echo "[+] No files found for dataset folder '${DATASET_FOLDER}'."
    exit 0
fi

FILE_COUNT=$(wc -l < "$ALL_FILES_TMP")
echo "[+] Total found across all pages: ${FILE_COUNT} file(s) matching prefix '${PATH_PREFIX}'."
echo "--------------------------------------------------------------------------"

# Print details for candidate files
while IFS=$'\t' read -r FILE_ID FILE_STATUS FILE_PATH; do
    echo "  - ID: ${FILE_ID} | Status: ${FILE_STATUS} | Path: ${FILE_PATH}"
done < "$ALL_FILES_TMP"

echo "--------------------------------------------------------------------------"

# The API only deletes files whose latest event is "uploaded"; any other file returns 404
DELETABLE_COUNT=$(awk -F'\t' '$2 == "uploaded"' "$ALL_FILES_TMP" | wc -l)
NOT_DELETABLE_COUNT=$((FILE_COUNT - DELETABLE_COUNT))
if [[ "$NOT_DELETABLE_COUNT" -gt 0 ]]; then
    echo "[!] Warning: ${NOT_DELETABLE_COUNT} file(s) are not in status 'uploaded' and will be skipped (the API only deletes uploaded files)."
fi
if [[ "$DELETABLE_COUNT" -eq 0 ]]; then
    echo "[+] No deletable files (status 'uploaded') found. Nothing to do."
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Handle Dry-Run Mode
# ------------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
    echo "[+] [DRY-RUN] Finished scanning. ${DELETABLE_COUNT} file(s) with status 'uploaded' would be deleted."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Confirmation & Deletion Loop
# ------------------------------------------------------------------------------
read -r -p "[?] Are you sure you want to permanently delete ${DELETABLE_COUNT} file(s)? (y/N): " CONFIRM || CONFIRM=""
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "[-] Deletion aborted by user."
    exit 0
fi

echo "[+] Starting file deletion..."
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

while IFS=$'\t' read -r FILE_ID FILE_STATUS FILE_PATH; do
    if [[ "$FILE_STATUS" != "uploaded" ]]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    if [[ -z "$FILE_ID" ]]; then
        echo "[-] Skipping entry with missing file ID (${FILE_PATH})."
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo -n "  Deleting File ID ${FILE_ID} (${FILE_PATH})... "

    DEL_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -X DELETE "$API_HOST/file/$USER_ID_ENC/$FILE_ID" </dev/null || true)

    DEL_STATUS=$(echo "$DEL_RESPONSE" | tail -n 1)
    DEL_BODY=$(echo "$DEL_RESPONSE" | sed '$d')

    if [[ "$DEL_STATUS" =~ ^2[0-9][0-9]$ ]]; then
        echo "[OK]"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "[FAILED] (HTTP $DEL_STATUS - $DEL_BODY)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$ALL_FILES_TMP"

echo "=========================================================================="
echo " Deletion Summary:"
echo "   Successfully deleted : ${SUCCESS_COUNT}"
echo "   Failed               : ${FAIL_COUNT}"
echo "   Skipped (not uploaded): ${SKIP_COUNT}"
echo "=========================================================================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi