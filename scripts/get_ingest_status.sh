#!/bin/bash

set -euo pipefail

# This script checks file status statistics during ingestion.

useCLI=false
user=""
dataset_folder=""

usage() {
  cat <<EOF
Usage: $0 [-usecli] -u <user> -d <dataset_folder>

Options:
  -u <user>             The username (required)
  -d <dataset_folder>   The dataset folder path (required)
  -usecli               Use the admin-api CLI instead of curl
EOF
}

# Parse arguments
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -u)
      user="$2"
      shift 2
      ;;
    -d)
      dataset_folder="$2"
      shift 2
      ;;
    -usecli)
      useCLI=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $key"
      usage
      exit 1
      ;;
  esac
done

# Ensure required args are set
if [ -z "$user" ] || [ -z "$dataset_folder" ]; then
  echo "Error: Both -u <user> and -d <dataset_folder> are required."
  usage
  exit 1
fi

# Check required environment variables
: "${ACCESS_TOKEN:?Error: ACCESS_TOKEN environment variable is not set.}"
: "${API_HOST:?Error: API_HOST environment variable is not set.}"

echo "API Host: $API_HOST"

# Main logic
if [ "$useCLI" = true ]; then
  # Using admin-api CLI
  sda-admin file list --user "$user" \
    | jq -r --arg ds "$dataset_folder" '.[] | select(.inboxPath | contains($ds)) | .fileStatus' \
    | sort | uniq -c
else
  # Using direct API call
  curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" \
       -X GET "$API_HOST/users/$user/files?path_prefix=$dataset_folder" \
    | jq -r '.[] | .fileStatus' \
    | sort | uniq -c
fi
