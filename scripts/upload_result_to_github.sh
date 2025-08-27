#!/bin/bash

set -e

encode_base64() {
  # Cross-platform base64 encoding without line breaks
  if command -v base64 >/dev/null 2>&1; then
    base64 "$1" | tr -d '\n'
  else
    echo "base64 command not found" >&2
    return 1
  fi
}

TOKEN="$GITHUB_TOKEN"   # or paste your PAT
REPO="nanjiangshu/my-plots"
BRANCH="main"

folder=$1
if [[ -z "$folder" ]]; then
  echo "Usage: $0 <folder>"
  exit 1
fi

# --- Check token ---
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Error: GITHUB_TOKEN is not set" >&2
  exit 1
fi

# Find newest file in the folder
newest_file=$(ls -t "$folder"/* 2>/dev/null | head -n1)
if [[ -z "$newest_file" ]]; then
  echo "No files found in $folder"
  exit 1
fi

# Use its modification time for DATE_TIME
DATE_TIME=$(date -r "$newest_file" +"%Y-%m-%d_%H-%M")

echo "Uploading to folder: plots/$DATE_TIME/ (based on $newest_file)"

for file in "$folder"/*.*; do
  filename=$(basename "$file")
  path="plots/$DATE_TIME/$filename"
  content=$(encode_base64 "$file")

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
done
