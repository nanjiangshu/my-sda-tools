#!/usr/bin/env bash
set -euo pipefail

USAGE="
Usage: $0 [-l dataset_id_list.txt] [dataset_folder_id1 dataset_folder_id2 ...]

Retrieve all METADATA XML files for given dataset folder IDs.
"

RUNDIR="$(dirname "$0")"
BINPATH="$(realpath "$RUNDIR")"

datasetIDListFile=""
datasetIDList=()

# -------------------------
# Parse arguments
# -------------------------
while getopts ":l:h" opt; do
  case "$opt" in
    l) datasetIDListFile="$OPTARG" ;;
    h) echo "$USAGE"; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG"; echo "$USAGE"; exit 1 ;;
  esac
done

shift $((OPTIND - 1))

# Dataset IDs from CLI
if [[ $# -gt 0 ]]; then
  datasetIDList+=("$@")
fi

# Dataset IDs from file
if [[ -n "$datasetIDListFile" ]]; then
  mapfile -t datasetIDList < <(tr -d '\r' < "$datasetIDListFile")
fi

if [[ ${#datasetIDList[@]} -eq 0 ]]; then
  echo "Error: No dataset IDs provided."
  exit 1
fi

# -------------------------
# Vault authentication
# -------------------------
if ! vault token renew >/dev/null 2>&1; then
  echo "Error: You must log in to vault.nbis.se before using this script"
  exit 1
fi

# -------------------------
# Temp files
# -------------------------
fileidFilePathListFile="fileid_filepath_list.txt"
fileidListFile="fileid_list.txt"

: > "$fileidFilePathListFile"

# -------------------------
# Query database
# -------------------------
for dataset_folder in "${datasetIDList[@]}"; do

  kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- \
    psql -tA -U postgres -d sda -c \
    "SELECT id, submission_file_path
     FROM sda.files
     WHERE submission_file_path LIKE '%${dataset_folder}/METADATA/%'" \
     >> "$fileidFilePathListFile"

done

# -------------------------
# Extract file IDs
# -------------------------
awk -F'|' '{print $1}' "$fileidFilePathListFile" > "$fileidListFile"

mapfile -t fileidList < "$fileidListFile"

# -------------------------
# Output directories
# -------------------------
outMetadata="metadata"
finalOutdir="data_all_metadata"

mkdir -p "$finalOutdir"

# -------------------------
# Retrieve files
# -------------------------
bash "$BINPATH/retrieve_c4ghfile_using_fileid.sh" \
  -outdir "$outMetadata" \
  "${fileidList[@]}"

# -------------------------
# Map file IDs to paths
# -------------------------
bash "$BINPATH/map_fileid_to_filepath.sh" \
  -m "$fileidFilePathListFile" \
  -s "$outMetadata" \
  -o "$finalOutdir"