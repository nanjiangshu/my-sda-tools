#!/bin/bash
# This script queries the checksums table in the sda database for a given accession ID. 

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <accessionID>"
    exit 1
fi
accessionID=$1
  
if [ "$accessionID" == "" ];then
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- \
psql -U postgres -t -d sda -c "
SELECT *
FROM sda.checksums
WHERE file_id = (
  SELECT id
  FROM sda.files
  WHERE stable_id = '$accessionID' 
)
"