#!/bin/bash
set -euo pipefail
# This script queries the checksums table in the sda database for a given file UUID.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <file-uuid>"
    exit 1
fi

file_uuid="$1"

if [ "$file_uuid" == "" ];then
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- \
psql -U postgres -t -d sda -c "
SELECT *
FROM sda.checksums
WHERE file_id = '$file_uuid'
"