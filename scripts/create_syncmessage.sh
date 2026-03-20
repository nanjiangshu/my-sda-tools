#!/usr/bin/env bash
# this script takes a list of stable IDs and a dataset ID, and creates JSON files in the format expected by the sync message system.
# The JSON files will have the following structure:
# {
#   "type": "mapping",
#   "dataset_id": "datasetID",
#   "accession_ids": ["stableID1", "stableID2", ...]
# }

usage="
Usage: $0 -d <datasetID> -f <stableid_list_file> [-o <output_prefix>] [-s <size>]
  -d <datasetID>            The dataset ID to include in the sync message.
  -f <stableid_list_file>   A file containing a list of stable IDs, one per line.
  -o <output_prefix>        The prefix for output JSON files.
  -s <size>                 Max IDs per file (default: 3000).
"

datasetID=""
stableid_list_file=""
output_prefix=""
chunk_size=3000

while getopts "d:f:o:s:" opt; do
    case $opt in
        d) datasetID="$OPTARG" ;;
        f) stableid_list_file="$OPTARG" ;;
        o) output_prefix="$OPTARG" ;;
        s) chunk_size="$OPTARG" ;;
        *) echo "$usage"; exit 1 ;;
    esac
done

# Validation
if [[ -z "${datasetID}" || ! -f "${stableid_list_file}" ]]; then
    echo "Error: Missing dataset ID or input file."
    echo "$usage"
    exit 1
fi

if [[ -z "${output_prefix}" ]]; then
    output_prefix="${stableid_list_file%.*}"
fi

# 1. Clean IDs (Cross-platform mktemp)
# On macOS mktemp needs a template; on Linux it's optional. Using a template works on both.
clean_file=$(mktemp /tmp/clean_ids.XXXXXX)
sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//' "${stableid_list_file}" > "$clean_file"

# 2. Create temporary directory for chunks
tmp_dir=$(mktemp -d /tmp/chunks.XXXXXX)

# 3. Universal Split
# We use only -l and -a (suffix length), which are standard on both systems.
# This will create files like: chunk_aa, chunk_ab, chunk_ac...
split -l "$chunk_size" -a 2 "$clean_file" "$tmp_dir/chunk_"

# 4. Process and Rename (The logic that makes it look like _00, _01)
counter=0
# Sort ensures we process aa, ab, ac in order
for chunk in $(ls "$tmp_dir"/chunk_* | sort); do
    # Format number to 2 digits (00, 01, 02...)
    suffix=$(printf "%02d" "$counter")
    current_output="${output_prefix}_${suffix}.json"

    # Use jq to build the JSON
    jq -Rnc '{type: "mapping", dataset_id: $dataset, accession_ids: [inputs]}' \
    --arg dataset "$datasetID" \
    < "$chunk" > "$current_output"

    echo "Generated: $current_output"
    counter=$((counter + 1))
done

# Cleanup
rm -f "$clean_file"
rm -rf "$tmp_dir"

echo "Success: Processed $((counter)) file(s)."