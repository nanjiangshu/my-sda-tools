#!/bin/bash
set -euo pipefail

# Description: This script fixes files stuck in submitted and archived status
usage="Usage: $0 -u <user_id> -d <dataset_folder>"

USER_ID=""
DATASET_FOLDER=""

while getopts "u:d:" opt; do
    case $opt in
        u) USER_ID="$OPTARG" ;;
        d) DATASET_FOLDER="$OPTARG" ;;
        *) echo "$usage"; exit 1 ;;
    esac
done

if [ -z "${USER_ID:-}" ] || [ -z "${DATASET_FOLDER:-}" ]; then
    echo "$usage"
    exit 1
fi

function fix_uploaded() {
    local fileidlist_file="$1"
    if [ ! -s "$fileidlist_file" ]; then
        echo "No files found in uploaded status for dataset folder $DATASET_FOLDER."
        return 0
    fi
    num_files=$(wc -l < "$fileidlist_file")
    echo "Found $num_files files in uploaded status. Re-ingesting them."
    # do you want to proceed?
    read -p "Do you want to proceed? (y/n) " -n 1 -r
    echo    # move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 0
    fi

    ((i=1))
    for fileid in $(cat "$fileidlist_file"); do
        echo "Processed file $i/$num_files: $fileid"
        sda-admin file ingest -fileid "$fileid"
        ((i++))
    done
}

function fix_submitted_or_archived() {
    local fileidlist_file="$1"
    if [ ! -s "$fileidlist_file" ]; then
        echo "No files found in submitted or archived status for dataset folder $DATASET_FOLDER."
        return 0
    fi
    num_files=$(wc -l < "$fileidlist_file")
    echo "Found $num_files files in submitted or archived status. Updating their status to uploaded and re-ingesting them."
    # do you want to proceed?
    read -p "Do you want to proceed? (y/n) " -n 1 -r
    echo    # move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 0
    fi

    # 2. Loop through the combined list
    ((i=1))
    for fileid in $(cat "$fileidlist_file"); do
        echo "Processed file $i/$num_files: $fileid"
        addevent_fileeventlog_with_fileid.sh "$fileid" uploaded
        sda-admin file ingest -fileid "$fileid"
        ((i++))
    done
}

query_userfiles.sh $USER_ID $DATASET_FOLDER > $DATASET_FOLDER.userfiles.txt

grep -iv "private" "$DATASET_FOLDER.userfiles.txt" | awk -F'|' '$4 ~ /^(submitted|archived)$/ { print $1 }' > t1.submitted_or_archived.fileidlist.txt
grep -iv "private" "$DATASET_FOLDER.userfiles.txt" | awk -F'|' '$4 ~ /^(uploaded)$/ { print $1 }' > t1.uploaded.fileidlist.txt

fix_uploaded t1.uploaded.fileidlist.txt
fix_submitted_or_archived t1.submitted_or_archived.fileidlist.txt
