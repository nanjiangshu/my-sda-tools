#!/bin/bash
# This script retrieves the correlation ID for a file based on its filepath, user, and accession ID.

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <filepath> <user> <accession_id>"
    exit 1
fi
filepath=$(echo "$1" | xargs)
user=$(echo "$2" | xargs)
accession_id=$(echo "$3" | xargs)
kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT DISTINCT correlation_id FROM sda.file_event_log e 
RIGHT JOIN sda.files f ON e.file_id = f.id
WHERE f.submission_file_path = '$filepath' AND f.submission_user = '$user' AND COALESCE(f.stable_id, '') = '$accession_id'
"