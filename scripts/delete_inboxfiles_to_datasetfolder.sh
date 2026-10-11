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
ACCESS_TOKEN=$(grep access_token ~/.sda/s3cmd-bp-download.conf  | awk '{print $NF}')


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


# Verify required tools and variables
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
    echo "[-] Error: \$ACCESS_TOKEN is not set or empty after sourcing init_bpsubmit.sh." >&2
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
# 1. Fetch File List via API
# ------------------------------------------------------------------------------
echo "[+] Querying files for path prefix '${DATASET_FOLDER}'..."

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -X GET "$API_HOST/users/$USER_ID/files?path_prefix=$DATASET_FOLDER")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_STATUS" -ne 200 ]]; then
    echo "[-] Error: API call to list files failed with HTTP status $HTTP_STATUS" >&2
    echo "    Response: $HTTP_BODY" >&2
    exit 1
fi

# Extract file IDs and paths (expecting JSON array of objects with fields like 'id' and 'path' or 'filepath')
FILE_ENTRIES=$(echo "$HTTP_BODY" | jq -c '.[]? // empty' || true)

if [[ -z "$FILE_ENTRIES" ]]; then
    echo "[+] No files found for dataset folder '${DATASET_FOLDER}'."
    exit 0
fi

FILE_COUNT=$(echo "$FILE_ENTRIES" | wc -l)
echo "[+] Found ${FILE_COUNT} file(s) matching prefix '${DATASET_FOLDER}':"
echo "--------------------------------------------------------------------------"

# Print details for each candidate file
echo "$FILE_ENTRIES" | while read -r file_obj; do
    FILE_ID=$(echo "$file_obj" | jq -r '.id // .fileid // .fileID')
    FILE_PATH=$(echo "$file_obj" | jq -r '.path // .filepath // .path_prefix // "N/A"')
    echo "  - ID: ${FILE_ID} | Path: ${FILE_PATH}"
done

echo "--------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Handle Dry-Run Mode
# ------------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
    echo "[+] [DRY-RUN] Finished scanning. ${FILE_COUNT} file(s) listed above would be deleted."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Confirmation & Deletion Loop
# ------------------------------------------------------------------------------
read -p "[?] Are you sure you want to permanently delete these ${FILE_COUNT} file(s)? (y/N): " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "[-] Deletion aborted by user."
    exit 0
fi

echo "[+] Starting file deletion..."
SUCCESS_COUNT=0
FAIL_COUNT=0

for file_obj in $FILE_ENTRIES; do
    FILE_ID=$(echo "$file_obj" | jq -r '.id // .fileid // .fileID')
    FILE_PATH=$(echo "$file_obj" | jq -r '.path // .filepath // "N/A"')

    if [[ -z "$FILE_ID" || "$FILE_ID" == "null" ]]; then
        echo "[-] Skipping entry: missing file ID."
        ((FAIL_COUNT++))
        continue
    fi

    echo -n "  Deleting File ID ${FILE_ID} (${FILE_PATH})... "

    DEL_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -X DELETE "$API_HOST/file/$USER_ID/$FILE_ID")

    DEL_STATUS=$(echo "$DEL_RESPONSE" | tail -n 1)
    DEL_BODY=$(echo "$DEL_RESPONSE" | sed '$d')

    if [[ "$DEL_STATUS" -eq 200 ]]; then
        echo "[OK]"
        ((SUCCESS_COUNT++))
    else
        echo "[FAILED] (HTTP $DEL_STATUS - $DEL_BODY)"
        ((FAIL_COUNT++))
    fi
done

echo "=========================================================================="
echo " Deletion Summary:"
echo "   Successfully deleted : ${SUCCESS_COUNT}"
echo "   Failed               : ${FAIL_COUNT}"
echo "=========================================================================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi