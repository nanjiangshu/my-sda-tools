#!/bin/bash

dataset_folder=$1
if [ "$dataset_folder" == "" ];then
    echo "Usage: $0 <dataset_folder>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
SELECT id, stable_id, submission_file_path FROM sda.files 
WHERE submission_file_path LIKE '%$dataset_folder/%'
" | awk 'NF' | sort -u |  tr '|' '\t' 
