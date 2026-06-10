#!/bin/bash
set -euo pipefail

# Fix files stuck in submitted and archived status

query_userfiles.sh $USER_ID $DATASET_FOLDER > $DATASET_FOLDER.userfiles.txt
grep -iv "private" "$DATASET_FOLDER.userfiles.txt" | awk -F'|' '$4 ~ /^(submitted|archived)$/ { print $1 }' > t1.submitted_or_archived.fileidlist.txt
if [ ! -s t1.submitted_or_archived.fileidlist.txt ]; then
    echo "No files found in submitted or archived status for dataset folder $DATASET_FOLDER."
    exit 0
fi
num_files=$(wc -l < t1.submitted_or_archived.fileidlist.txt)
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
for fileid in $(cat t1.submitted_or_archived.fileidlist.txt); do
    echo "Processed file $i/$num_files: $fileid"
    addevent_fileeventlog_with_fileid.sh "$fileid" uploaded
    sda-admin file ingest -fileid "$fileid"
    ((i++))
done  
