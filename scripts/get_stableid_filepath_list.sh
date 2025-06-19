#!/bin/bash
# This script retrieves the list of stable IDs and file paths for an already ingested dataset
dataset_folder=$1
if [ "$dataset_folder" == "" ];then
    echo "Usage: $0 <dataset_folder>" 
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -d sda -c "
SELECT message FROM sda.file_event_log 
WHERE message->>'filepath' LIKE '%${dataset_folder}%' 
AND event = 'ready';
" | grep accession_id | jq -r '.accession_id + " " + (if .filepath | startswith("DATASET_") then .filepath else .filepath | sub("^[^/]+/"; "")
end)'
