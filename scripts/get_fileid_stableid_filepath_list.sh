#!/bin/bash

usage="Usage: $0 [OPTIONS] <dataset_folder>
Options:
    -h, --help              Show this help message and exit
    -show-last-modified     Show the last modified date of the files
"
# argument parsing
show_last_modified=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) echo "$usage"; exit 0 ;;
        -show-last-modified) show_last_modified=true ;;
        *) dataset_folder="$1" ;;
    esac
    shift
done

if [ -z "$dataset_folder" ]; then
    echo "ERROR: dataset_folder is required"
    echo "$usage"
    exit 1
fi

if [ "$show_last_modified" = false ]; then
    kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
    SELECT id, stable_id, submission_file_path FROM sda.files 
    WHERE submission_file_path LIKE '%$dataset_folder/%'
    AND stable_id IS NOT NULL
    AND submission_file_path IS NOT NULL
    " | awk 'NF' | sort -u |  tr '|' '\t' 
else
    kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
    SELECT id, stable_id, submission_file_path, last_modified FROM sda.files 
    WHERE submission_file_path LIKE '%$dataset_folder/%'
    AND stable_id IS NOT NULL
    AND submission_file_path IS NOT NULL
    " | awk 'NF' | sort -u |  tr '|' '\t' 
fi

