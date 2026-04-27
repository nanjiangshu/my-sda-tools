#!/bin/bash
set -euo pipefail

usage="Usage: $0 -dataset-id <dataset_id> [-dry-run] [-all | -file-id-list <file_id_list_file>]"

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

# Validation: Must have a dataset ID AND either -all or -file-id-list
if [[ -z "$dataset_id" ]] || { [[ "$is_all" = false ]] && [[ -z "$file_id_list_file" ]]; }; then
    echo "Error: Missing required arguments."
    echo "$usage"
    exit 1
fi

# sanity check for dataset_id format (assuming it should be something like DATASET_1234abc)
if [[ ! "$dataset_id" =~ ^DATASET_[a-zA-Z0-9]+$ ]]; then
    echo "Error: dataset_id '$dataset_id' does not match expected format (e.g., DATASET_1234abc)."
    exit 1
fi

# Lookup Digital ID (using -tA for clean output)
digit_dataset_id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
SELECT id FROM sda.datasets WHERE stable_id = '$dataset_id'
")

if [[ -z "$digit_dataset_id" ]]; then
    echo "Error: No dataset found with stable_id '$dataset_id'"
    exit 1
fi

# Logic for -all
if [[ "$is_all" = true ]]; then
    if [[ "$is_dry_run" = true ]]; then
        echo "Dry run: Counting ALL files for dataset $dataset_id ($digit_dataset_id)"
        kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
        SELECT count(*) AS rows_to_be_removed FROM sda.file_dataset WHERE dataset_id = $digit_dataset_id;"
    else
        echo "PERMANENTLY deleting all files for dataset $dataset_id ($digit_dataset_id)..."
        kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
        DELETE FROM sda.file_dataset WHERE dataset_id = $digit_dataset_id;"
    fi
    exit 0 # We are done if -all was processed
fi

# Logic for -file-id-list
if [[ ! -f "$file_id_list_file" ]]; then
    echo "Error: File '$file_id_list_file' not found."
    exit 1
fi

if [[ "$is_dry_run" = true ]]; then
    echo "Dry run: Counting specific files from $file_id_list_file for dataset $dataset_id"
    cat "$file_id_list_file" | kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
    CREATE TEMP TABLE to_delete (f_id UUID);
    COPY to_delete FROM STDIN;
    SELECT count(*) AS rows_to_be_removed FROM sda.file_dataset
    WHERE dataset_id = $digit_dataset_id AND file_id IN (SELECT f_id FROM to_delete);"
else
    echo "Deleting specific files from $file_id_list_file for dataset $dataset_id..."
    cat "$file_id_list_file" | kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -c "
    CREATE TEMP TABLE to_delete (f_id UUID);
    COPY to_delete FROM STDIN;
    DELETE FROM sda.file_dataset
    WHERE dataset_id = $digit_dataset_id AND file_id IN (SELECT f_id FROM to_delete);"
fi
