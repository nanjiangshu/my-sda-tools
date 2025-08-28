#!/bin/bash

set -euo pipefail

encode_base64() {
  # Cross-platform base64 encoding without line breaks
  if command -v base64 >/dev/null 2>&1; then
    base64 "$1" | tr -d '\n'
  else
    echo "base64 command not found" >&2
    return 1
  fi
}

# Check required environment
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN is not defined."
  exit 1
fi

TOKEN="$GITHUB_TOKEN"
REPO="nanjiangshu/my-plots"
BRANCH="main"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <folder>"
  exit 1
fi

folder="$1"
if [[ ! -d "$folder" ]]; then
  echo "Error: $folder is not a directory."
  exit 1
fi

# Allowed files
allowed_files=(
  "plot_runtime_boxplot.pdf"
  "plot_runtime_boxplot.png"
  "plot_upload_status.pdf"
  "plot_upload_status.png"
  "sda_cli_200M.runtime.txt"
  "sda_cli_200M.txt"
  "sda_cli_200M.upload_status.txt"
  "sda_cli_20M.runtime.txt"
  "sda_cli_20M.txt"
  "sda_cli_20M.upload_status.txt"
  "sda_cli_2M.runtime.txt"
  "sda_cli_2M.txt"
  "sda_cli_2M.upload_status.txt"
  "info.json"
)

# Find newest file among allowed
newest_file=$(ls -t "${folder}"/* 2>/dev/null | grep -F -f <(printf "%s\n" "${allowed_files[@]}") | head -n 1 || true)
if [[ -z "$newest_file" ]]; then
  echo "Error: No allowed files found in $folder"
  exit 1
fi

DATE_TIME=$(date -r "$newest_file" +"%Y-%m-%d_%H-%M")

echo "Using DATE_TIME=$DATE_TIME (from newest allowed file: $(basename "$newest_file"))"

# Upload allowed files
for filename in "${allowed_files[@]}"; do
  file="$folder/$filename"
  if [[ -f "$file" ]]; then
    path="plots/$DATE_TIME/$filename"
    content=$(encode_base64 "$file")

    echo "Uploading $filename → $path"

    curl -s -X PUT \
      -H "Authorization: token $TOKEN" \
      -H "Content-Type: application/json" \
      "https://api.github.com/repos/$REPO/contents/$path" \
      -d @- <<EOF
{
  "message": "Add plot $filename at $DATE_TIME",
  "content": "$content",
  "branch": "$BRANCH"
}
EOF
  else
    echo "Skipping missing file: $filename"
  fi
done
