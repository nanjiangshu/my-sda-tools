#!/bin/bash
# This script queries the files table in the sda database for a given file accession ID 
accession_id=$1

if [ "$accession_id" == "" ];then
    echo "Usage: $0 <file_accession_id>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres  -d sda -c "
SELECT id, stable_id, submission_user, submission_file_path,  archive_file_path FROM sda.files
WHERE stable_id = '$accession_id'
"

