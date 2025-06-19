#!/bin/bash

# This script queries the file_event_log table in the sda database for a given file ID.
file_id=$1

if [ "$file_id" == "" ];then
    echo "Usage: $0 <file_id>"
    exit 1
fi

file_id=$(echo "$file_id" | awk '{$1=$1;print}')

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.file_event_log
WHERE file_id = '$file_id'
ORDER BY started_at DESC
"

