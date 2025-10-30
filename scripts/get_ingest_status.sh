#!/bin/bash

set -euo pipefail

# this script checks the file status statistics during ingestion

usage="""
Usage: $0 <user> <dataset_folder>
"""

if [ $# -ne 2 ]; then
  echo "$usage"
  exit 1
fi

user="$1"
dataset_folder="$2"

sda-admin file list --user "$user" | jq -r --arg ds "$dataset_folder" '.[] | select((.inboxPath | contains($ds))) | .fileStatus' | sort | uniq -c  