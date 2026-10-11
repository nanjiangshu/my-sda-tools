#!/usr/bin/env bash

set -euo pipefail

# ------------------------------------------------------------------------------
# Usage / Help Function
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -d DATASET_FOLDER -n MAIL_UPLOADER_NAME -m MAIL_UPLOADER"
    echo "  -d  Dataset folder name (Mandatory)"
    echo "  -n  Mail uploader name (Mandatory)"
    echo "  -m  Mail uploader email (Mandatory)"
    exit 1
}

# Parse Command-Line Options
DATASET_FOLDER=""
MAIL_UPLOADER_NAME=""
MAIL_UPLOADER=""

while getopts ":d:n:m:h" opt; do
    case "${opt}" in
        d) DATASET_FOLDER="${OPTARG}" ;;
        n) MAIL_UPLOADER_NAME="${OPTARG}" ;;
        m) MAIL_UPLOADER="${OPTARG}" ;;
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

# Validate Mandatory Flags
if [[ -z "$DATASET_FOLDER" || -z "$MAIL_UPLOADER_NAME" || -z "$MAIL_UPLOADER" ]]; then
    echo "[-] Error: Missing mandatory arguments." >&2
    usage
fi

# ------------------------------------------------------------------------------
# Check Current Working Directory
# ------------------------------------------------------------------------------
CURRENT_DIR=$(basename "$PWD")
if [[ "$CURRENT_DIR" != "$DATASET_FOLDER" ]]; then
    echo "[-] Warning: Current directory ('$CURRENT_DIR') does not match requested DATASET_FOLDER ('$DATASET_FOLDER'). Aborting execution." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Environment Setup & Command Pre-checks
# ------------------------------------------------------------------------------
if [[ -f "$HOME/.sda/init_bpsubmit_prod.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.sda/init_bpsubmit_prod.sh"
else
    echo "[-] Error: $HOME/.sda/init_bpsubmit_prod.sh not found!" >&2
    exit 1
fi

VALIDATOR_CMD="${validator:-validator}"

# List of all required commands to pre-check
REQUIRED_COMMANDS=(
    "s3cmd"
    "grep"
    "awk"
    "sed"
    "tr"
    "stat"
    "get_filelist_for_datasetfolder.sh"
    "vault"
    "$VALIDATOR_CMD"
)

MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then
    echo "[-] Error: The following required commands/tools are missing or not in PATH:" >&2
    for missing_cmd in "${MISSING_COMMANDS[@]}"; do
        echo "    - $missing_cmd" >&2
    done
    exit 1
fi

# -------------------------
# Vault authentication
# -------------------------
if ! vault token renew >/dev/null 2>&1; then
  echo "Error: You must log in to vault.nbis.se before using this script"
  exit 1
fi


echo "=========================================================================="
echo " Processing Dataset: ${DATASET_FOLDER}"
echo "=========================================================================="

# ------------------------------------------------------------------------------
# Refresh bpprod-inbox-all.s3.txt (Only if missing or older than 1 day / 86400s)
# ------------------------------------------------------------------------------
S3_LIST_FILE="../bpprod-inbox-all.s3.txt"
REGENERATE_S3_LIST=false

if [[ ! -f "$S3_LIST_FILE" ]]; then
    REGENERATE_S3_LIST=true
else
    # Check if file modification time is older than 1 day (86400 seconds)
    file_age=$(($(date +%s) - $(stat -c %Y "$S3_LIST_FILE")))
    if (( file_age > 86400 )); then
        REGENERATE_S3_LIST=true
    fi
fi

if [[ "$REGENERATE_S3_LIST" == true ]]; then
    echo "[+] Regenerating ${S3_LIST_FILE} via s3cmd..."
    s3cmd -c ~/.sda/s3cmd-bp-master-inbox.conf ls -r s3://inbox > "$S3_LIST_FILE"
else
    echo "[+] Using cached ${S3_LIST_FILE} (less than 1 day old)."
fi

# ------------------------------------------------------------------------------
# Extract USER_ID
# ------------------------------------------------------------------------------
USER_ID=$(grep "$DATASET_FOLDER" "$S3_LIST_FILE" | head -n 1 | awk '{print $NF}' | awk -F'/' '{print $4}' | sed 's/_lifescience-ri.eu/@lifescience-ri.eu/g' || true)

if [[ -z "$USER_ID" ]]; then
    echo "[-] Error: Could not determine USER_ID for ${DATASET_FOLDER} from ${S3_LIST_FILE}." >&2
    exit 1
fi

echo "[+] Retrieved USER_ID: ${USER_ID}"

# ------------------------------------------------------------------------------
# Step 1: Generate File List
# ------------------------------------------------------------------------------
user_underscore=$(echo "$USER_ID" | tr '@' '_')

echo "[+] Generating file list for user: ${user_underscore}..."
get_filelist_for_datasetfolder.sh -u "$user_underscore" "$DATASET_FOLDER"

# ------------------------------------------------------------------------------
# Step 2: Dry-run Validation
# ------------------------------------------------------------------------------
echo "[+] Running dry-run validation..."
DRY_RUN_OUTPUT=$("$VALIDATOR_CMD" -c prod \
    -u "$USER_ID" \
    -d "$DATASET_FOLDER" \
    -t "$ACCESS_TOKEN" \
    -n "$MAIL_UPLOADER_NAME" \
    -e "$MAIL_UPLOADER" \
    --dry-run 2>&1)

echo "$DRY_RUN_OUTPUT"

# Verify dry-run output
if ! echo "$DRY_RUN_OUTPUT" | grep -q "All checks passed"; then
    echo "[-] Validation dry-run failed or did not report 'All checks passed'. Aborting." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 3: Backup XML/XSD Folders & Execute Final Submission
# ------------------------------------------------------------------------------
echo "[+] Dry-run passed. Backing up xml-files and xsd-files..."
mkdir -p bak
if [[ -d "xml-files" ]]; then
    mv xml-files bak/
fi
if [[ -d "xsd-files" ]]; then
    mv xsd-files bak/
fi

echo "[+] Executing production submission..."
"$VALIDATOR_CMD" -c prod \
    -u "$USER_ID" \
    -d "$DATASET_FOLDER" \
    -t "$ACCESS_TOKEN" \
    -n "$MAIL_UPLOADER_NAME" \
    -e "$MAIL_UPLOADER"

# ------------------------------------------------------------------------------
# Step 4: Extract Metadata & Write Info File
# ------------------------------------------------------------------------------
echo "[+] Retrieving metadata for dataset info file..."

# Extract DATASET_ID from dataset_id.txt (checking root and backup locations)
DATASET_ID=""
if [[ -f "dataset_id.txt" ]]; then
    DATASET_ID=$(tr -d '\r\n' < dataset_id.txt)
elif [[ -f "bak/dataset_id.txt" ]]; then
    DATASET_ID=$(tr -d '\r\n' < bak/dataset_id.txt)
else
    echo "[!] Warning: dataset_id.txt not found." >&2
fi

# Extract MAIL_UPLOADER_ORGANIZATION_NAME from xml-files/organisation.xml
MAIL_UPLOADER_ORGANIZATION_NAME=""
ORG_XML=""
if [[ -f "bak/xml-files/organisation.xml" ]]; then
    ORG_XML="bak/xml-files/organisation.xml"
elif [[ -f "xml-files/organisation.xml" ]]; then
    ORG_XML="xml-files/organisation.xml"
fi

if [[ -n "$ORG_XML" ]]; then
    MAIL_UPLOADER_ORGANIZATION_NAME=$(grep -oP '(?<=<NAME>).*?(?=</NAME>)' "$ORG_XML" 2>/dev/null || sed -n 's/.*<NAME>\(.*\)<\/NAME>.*/\1/p' "$ORG_XML")
else
    echo "[!] Warning: xml-files/organisation.xml not found." >&2
fi

# Write summary file
INFO_FILE="${DATASET_FOLDER}.info.conf"
cat << EOF > "$INFO_FILE"
export DATASET_FOLDER=${DATASET_FOLDER}
export USER_ID=${USER_ID}
export DATASET_ID=${DATASET_ID}
export MAIL_UPLOADER_NAME="${MAIL_UPLOADER_NAME}"
export MAIL_UPLOADER="${MAIL_UPLOADER}"
export MAIL_UPLOADER_ORGANIZATION_NAME="${MAIL_UPLOADER_ORGANIZATION_NAME}"
EOF

echo "[+] Successfully created summary file: ${INFO_FILE}"
cat "$INFO_FILE"