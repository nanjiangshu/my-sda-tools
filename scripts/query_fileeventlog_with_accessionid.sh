#!/bin/bash
# This script queries the file_event_log table in the sda database for a given accession ID.

accessionID=$1

if [ "$accessionID" == "" ];then
    echo "Usage: $0 <accessionID>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- \
psql -U postgres -t -d sda -c "
SELECT *
FROM sda.file_event_log
WHERE file_id = (
  SELECT id
  FROM sda.files
  WHERE stable_id = '$accessionID'
)
ORDER BY started_at DESC;
"