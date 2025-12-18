#!/bin/bash
# This script get stable_id and filepath (without username) that will be provided to the submitter for a given dataset folder.

dataset_folder=$1
if [ "$dataset_folder" == "" ];then
    echo "Usage: $0 <dataset_folder>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
SELECT stable_id, submission_file_path FROM sda.files
WHERE submission_file_path LIKE '%$dataset_folder/%'
  AND stable_id IS NOT NULL
  AND submission_file_path IS NOT NULL
" | awk 'NF' | sort -u |  tr '|' '\t'
