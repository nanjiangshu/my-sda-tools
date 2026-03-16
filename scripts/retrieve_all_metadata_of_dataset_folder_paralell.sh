#!/usr/bin/env bash
set -euo pipefail

USAGE="
Usage:
  $0 [-l dataset_id_list.txt] [dataset_folder_id1 dataset_folder_id2 ...]

Retrieve all METADATA XML files for given dataset folder IDs.
"

RUNDIR="$(dirname "$0")"
BINPATH="$(realpath "$RUNDIR")"

datasetIDListFile=""
datasetIDList=()

# -----------------------------
# Parse arguments
# -----------------------------
while getopts ":l:h" opt; do
  case "$opt" in
    l) datasetIDListFile="$OPTARG" ;;
    h) echo "$USAGE"; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG"; echo "$USAGE"; exit 1 ;;
  esac
done

shift $((OPTIND - 1))

# dataset IDs from CLI
if [[ $# -gt 0 ]]; then
  datasetIDList+=("$@")
fi

# dataset IDs from file
if [[ -n "$datasetIDListFile" ]]; then
  mapfile -t datasetIDList < <(tr -d '\r' < "$datasetIDListFile")
fi

if [[ ${#datasetIDList[@]} -eq 0 ]]; then
  echo "Error: No dataset IDs provided"
  exit 1
fi

# -----------------------------
# Vault authentication check
# -----------------------------
echo "Checking Vault token..."

if ! vault token renew >/dev/null 2>&1; then
  echo "Error: You must log in to vault.nbis.se before using this script"
  exit 1
fi

# -----------------------------
# Temp files
# -----------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fileidFilePathListFile="$tmpdir/fileid_filepath_list.txt"
fileidListFile="$tmpdir/fileid_list.txt"

# -----------------------------
# Build SQL condition
# -----------------------------
echo "Preparing dataset filter..."

like_conditions=()

for ds in "${datasetIDList[@]}"; do
  like_conditions+=("submission_file_path LIKE '%${ds}/METADATA/%'")
done

sql_filter=$(IFS=" OR "; echo "${like_conditions[*]}")

# -----------------------------
# Query database
# -----------------------------
echo "Querying database..."

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- \
psql -tA -U postgres -d sda -c "
SELECT id, submission_file_path
FROM sda.files
WHERE $sql_filter
" > "$fileidFilePathListFile"

if [[ ! -s "$fileidFilePathListFile" ]]; then
  echo "No metadata files found."
  exit 0
fi

awk -F'|' '{print $1}' "$fileidFilePathListFile" > "$fileidListFile"

mapfile -t fileidList < "$fileidListFile"

echo "Found ${#fileidList[@]} metadata files."

# -----------------------------
# Output directories
# -----------------------------
outMetadata="metadata"
finalOutdir="data_all_metadata"

mkdir -p "$outMetadata"
mkdir -p "$finalOutdir"

# -----------------------------
# Parallel file retrieval
# -----------------------------
echo "Retrieving metadata files..."

parallel_jobs=8

printf "%s\n" "${fileidList[@]}" | \
xargs -n 20 -P "$parallel_jobs" bash "$BINPATH/retrieve_c4ghfile_using_fileid.sh" -outdir "$outMetadata"

# -----------------------------
# Map file IDs to paths
# -----------------------------
echo "Mapping files to dataset paths..."

bash "$BINPATH/map_fileid_to_filepath.sh" \
  -m "$fileidFilePathListFile" \
  -s "$outMetadata" \
  -o "$finalOutdir"

echo "Done."
echo "All metadata stored in: $finalOutdir"
