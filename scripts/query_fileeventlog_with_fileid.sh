#!/bin/bash

# This script queries the file_event_log table in the sda database for a given file ID.

# Check if a file_id was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file_id>"
    exit 1
fi

# Remove leading/trailing whitespaces
file_id=$(echo "$1" | xargs)

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.file_event_log
WHERE file_id = '$file_id'
ORDER BY started_at DESC
"
