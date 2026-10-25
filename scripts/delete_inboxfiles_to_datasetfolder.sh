#!/usr/bin/env bash

# This script deletes files from S3Inbox for a specified dataset folder for a given user.
# It supports a dry-run mode to list files that would be deleted without actually deleting them.
set -euo pipefail

# ------------------------------------------------------------------------------
# Usage / Help
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -d DATASET_FOLDER [-u USER_ID] [-t TARGET] [-n] [-h] [-p API_HOST]"
    echo "  -d  Dataset folder name (Mandatory)"
    echo "  -u  User ID / Username, e.g. user@lifescience-ri.eu"
    echo "      (Optional, retrieved from the S3 inbox listing if not provided)"
    echo "  -t  Target: bp-prod or bp-staging (Optional, default: bp-prod)"
    echo "  -n  Dry-run mode (Only list files that would be deleted, do not delete)"
    echo "  -p  API host URL (Optional, overrides the default API host of the target)"
    echo "  -h  Show this help message"
    exit 1
}

DATASET_FOLDER=""
USER_ID=""
TARGET="bp-prod"
API_HOST_OVERRIDE=""
DRY_RUN=false

while getopts ":d:u:t:p:nh" opt; do
    case "${opt}" in
        d) DATASET_FOLDER="${OPTARG}" ;;
        u) USER_ID="${OPTARG}" ;;
        t) TARGET="${OPTARG}" ;;
        p) API_HOST_OVERRIDE="${OPTARG}" ;;
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

if [[ -z "$DATASET_FOLDER" ]]; then
    echo "[-] Error: -d DATASET_FOLDER is mandatory." >&2
    usage
fi

# ------------------------------------------------------------------------------
# Target Specific Settings
# ------------------------------------------------------------------------------
case "$TARGET" in
    bp-prod)
        API_HOST="https://api.bp.nbis.se"
        TOKEN_CONF="$HOME/.sda/s3cmd-bp-download.conf"
        S3_INBOX_BUCKET="s3://inbox"
        S3_LIST_FILENAME="bpprod-inbox-all.s3.txt"
        ;;
    bp-staging)
        API_HOST="https://staging-api.bp.nbis.se"
        TOKEN_CONF="$HOME/.sda/s3cmd-bp-staging-download.conf"
        S3_INBOX_BUCKET="s3://staging-inbox"
        S3_LIST_FILENAME="bpstaging-inbox-all.s3.txt"
        ;;
    *)
        echo "[-] Error: Unknown target '${TARGET}'. Supported: bp-prod, bp-staging." >&2
        usage
        ;;
esac

if [[ -n "$API_HOST_OVERRIDE" ]]; then
    API_HOST="$API_HOST_OVERRIDE"
fi
ACCESS_TOKEN=$(grep access_token "$TOKEN_CONF" 2>/dev/null | awk '{print $NF}' || true)

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
if [[ -z "$USER_ID" ]]; then
    REQUIRED_TOOLS+=("s3cmd")
fi
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
    echo "[-] Error: \$ACCESS_TOKEN could not be extracted from ${TOKEN_CONF}." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Retrieve USER_ID from the S3 inbox listing if not provided
# ------------------------------------------------------------------------------
if [[ -z "$USER_ID" ]]; then
    # Share the cached listing with bpsubmit_submit.sh, which keeps it in the
    # parent directory of the dataset folder
    if [[ "$(basename "$PWD")" == "$DATASET_FOLDER" ]]; then
        S3_LIST_FILE="../${S3_LIST_FILENAME}"
    else
        S3_LIST_FILE="./${S3_LIST_FILENAME}"
    fi

    # Refresh the listing only if missing or older than 1 day (86400s)
    REGENERATE_S3_LIST=false
    if [[ ! -f "$S3_LIST_FILE" ]]; then
        REGENERATE_S3_LIST=true
    else
        file_age=$(($(date +%s) - $(stat -c %Y "$S3_LIST_FILE")))
        if (( file_age > 86400 )); then
            REGENERATE_S3_LIST=true
        fi
    fi

    if [[ "$REGENERATE_S3_LIST" == true ]]; then
        echo "[+] Regenerating ${S3_LIST_FILE} via s3cmd..."
        s3cmd -c ~/.sda/s3cmd-bp-master-inbox.conf ls -r "$S3_INBOX_BUCKET" > "$S3_LIST_FILE"
    else
        echo "[+] Using cached ${S3_LIST_FILE} (less than 1 day old)."
    fi

    # Match the folder as a whole path component, so "DS1" does not match "DS10".
    # Paths look like s3://<bucket>/<user>/<dataset_folder>/...
    USER_IDS=$(awk '{print $NF}' "$S3_LIST_FILE" | grep -F "/${DATASET_FOLDER}/" \
        | awk -F'/' '{print $4}' | sed 's/_lifescience-ri.eu/@lifescience-ri.eu/g' | sort -u || true)

    if [[ -z "$USER_IDS" ]]; then
        echo "[-] Error: Could not determine USER_ID for ${DATASET_FOLDER} from ${S3_LIST_FILE}." >&2
        exit 1
    fi
    if [[ $(echo "$USER_IDS" | wc -l) -gt 1 ]]; then
        echo "[-] Error: Dataset folder ${DATASET_FOLDER} exists for more than one user. Specify one with -u:" >&2
        echo "$USER_IDS" | sed 's/^/    - /' >&2
        exit 1
    fi
    USER_ID="$USER_IDS"
    echo "[+] Retrieved USER_ID: ${USER_ID}"
fi

echo "=========================================================================="
echo " Dataset Deletion Tool"
echo " Target         : ${TARGET}"
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