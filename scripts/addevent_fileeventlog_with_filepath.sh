#!/bin/bash
set -euo pipefail

# This script adds a new file_event_log entry by looking up metadata in sda.files.
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <filepath> <event_type>"
    exit 1
fi

filepath=$1
event_type=$2

echo "Logging event '$event_type' for file: $filepath"

# Single kubectl call to the Read-Write service
# Note: we omit success and started_at to let the DB defaults handle them
kubectl -n sda-prod exec svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
INSERT INTO sda.file_event_log (file_id, event, user_id)
SELECT id, '$event_type', submission_user
FROM sda.files
WHERE submission_file_path = '$filepath'
   OR submission_file_path LIKE '%$filepath%'
LIMIT 1;
"

echo "Log entry created for event '$event_type' for file $filepath."