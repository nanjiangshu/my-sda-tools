#!/bin/bash
# Description: This script queries the file_event_log table in the sda database for a specific filepath and output the event in the order of creation time.

usage="""
Usage: $0 <filepath>
"""

filepath=$1

if [ "$filepath" == "" ];then
    echo "$usage"
    exit 1
fi

file_path=$(echo "$filepath" | xargs)

file_id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT file_id FROM sda.file_event_log 
WHERE message->>'filepath' LIKE '%"$file_path"%'
LIMIT 1
")

file_id=$(echo "$file_id" | awk '{$1=$1;print}')

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
SELECT event FROM sda.file_event_log
WHERE file_id = '$file_id'
ORDER BY started_at DESC
"
