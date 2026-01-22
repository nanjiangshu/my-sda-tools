#!/usr/bin/env bash

set -euo pipefail
# This script generates sync message json files for each item in the input file.

usage="
Usage: $0 -d <datasetID> -f <stableid_list_file> -o <output_json_file>
  -d <datasetID>            The dataset ID to include in the sync message.
  -f <stableid_list_file>   A file containing a list of stable IDs, one per line.
  -o <output_json_file>     The output JSON file to write the sync message to, default is <stableid_list_file>.json
"

if [ "$#" -lt 2 ]; then
    echo "$usage"
    exit 1
fi
datasetID=""
stableid_list_file=""
output_json_file=""

while getopts "d:f:o:" opt; do
    case $opt in
        d) datasetID="$OPTARG" ;;
        f) stableid_list_file="$OPTARG" ;;
        o) output_json_file="$OPTARG" ;;
        *) echo "$usage"
           exit 1 ;;
    esac
done

if [ -z "${datasetID:-}" ]; then
    echo "Error: Dataset ID is required!"
    echo "$usage"
    exit 1
fi  

if [ ! -f "${stableid_list_file:-}" ]; then
    echo "Error: File '${stableid_list_file:-}' not found!"
    exit 1
fi

if [ -z "${output_json_file:-}" ]; then
    output_json_file="${stableid_list_file}.json"
fi

# remove trailing white space both beginning and end for the stableid list file
sed -i 's/^[[:space:]]\+//;s/[[:space:]]\+$//' "${stableid_list_file}"

# use the -c flag for jq so that the result is in one line
jq -Rnc '{type: "mapping", dataset_id: $dataset, accession_ids: [inputs]}' \
--arg dataset "$datasetID" \
<  "${stableid_list_file}" > "${output_json_file}"

echo "Generated sync message file: ${output_json_file}"