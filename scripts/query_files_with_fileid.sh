#!/bin/bash
# This script queries the files table in the sda database for a given file ID.
file_id=$1

if [ "$file_id" == "" ];then
    echo "Usage: $0 <file_id>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres  -d sda -c "
SELECT * FROM sda.files
WHERE id = '$file_id'
"

