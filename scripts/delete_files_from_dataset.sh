#!/bin/bash
set -euo pipefail

# This script delete files from sda.file_dataset table for a given dataset_id
# and list of file_ids. The file_ids are read from a file specified as an
# argument.

# usage: ./delete_files_from_dataset.sh -dataset-id <dataset_id> [-dry-run] [-all | -file-id-list <file_id_list_file>]
# when -all is specified, it will delete all files associated with the dataset_id

usage="Usage: $0 -dataset-id <dataset_id> [-dry-run] [-all | -file-id-list <file_id_list_file>]"

# argument parsing
dataset_id=""
file_id_list_file=""
is_all=false
is_dry_run=false

if [[ "$#" -eq 0 ]]; then
    echo "$usage"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dataset-id) dataset_id="$2"; shift ;;
        -file-id-list) file_id_list_file="$2"; shift ;;
        -all) is_all=true ;;
        -dry-run) is_dry_run=true ;;
        *) echo "Unknown parameter: $1"; echo "$usage"; exit 1 ;;
    esac
    shift
done

digit_dataset_id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
SELECT id FROM sda.datasets WHERE stable_id = '$dataset_id'
")

if [[ -z "$digit_dataset_id" ]]; then
    echo "Error: No dataset found with stable_id '$dataset_id'"
    exit 1
fi

if [[ "$is_all" = true ]]; then
    echo "Deleting all files associated with dataset_id '$dataset_id' (id: $digit_dataset_id)"
    if [[ "$is_dry_run" = true ]]; then
        echo "Dry run: showing how many rows would be deleted"
        kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
SELECT count(*) AS rows_to_remove 
FROM sda.file_dataset 
WHERE dataset_id = $digit_dataset_id;
"
    else
        kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
DELETE FROM sda.file_dataset 
WHERE dataset_id = $digit_dataset_id;
"
    exit 0
fi

# Try running a count query first to check if the dataset_id is valid and if there are files to delete
if [[ "$is_dry_run" = true ]]; then
    echo "Dry run: showing how many rows would be deleted for dataset_id '$dataset_id' (id: $digit_dataset_id)"
    cat "$file_id_list_file" | kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
CREATE TEMP TABLE to_delete (f_id UUID);
COPY to_delete FROM STDIN;
SELECT count(*) AS rows_to_remove 
FROM sda.file_dataset 
WHERE dataset_id = $digit_dataset_id 
AND file_id IN (SELECT f_id FROM to_delete);"
else

    cat "$file_id_list_file" | kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
CREATE TEMP TABLE to_delete (f_id UUID);
COPY to_delete FROM STDIN;

DELETE FROM sda.file_dataset 
WHERE dataset_id = $digit_dataset_id
AND file_id IN (SELECT f_id FROM to_delete);
"
fi