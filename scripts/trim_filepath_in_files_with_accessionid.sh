#!/bin/bash
# This script trims the submission_file_path in the sda.files table for a given accession ID. 
accession_id=$1

if [ "$accession_id" == "" ];then
    echo "Usage: $0 <file_accession_id>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
UPDATE sda.files SET submission_file_path = TRIM(submission_file_path)
WHERE stable_id = '$accession_id'" 
