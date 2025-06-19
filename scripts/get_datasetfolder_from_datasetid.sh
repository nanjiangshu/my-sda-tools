# This script retrieves the folder path for a given dataset ID  
dataset_stableID=$1
if [ "$dataset_stableID" == "" ];then
    echo "Usage: $0 <dataset_stableID>"
    exit 1
fi

# get the dataset ID (int) from the stable ID
id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -d sda -t -c "
SELECT id FROM sda.datasets 
WHERE stable_id = '$dataset_stableID'
")

# remove leading and trailing whitespace
id=$(echo "$id" | awk '{$1=$1;print}')

file_id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT file_id FROM sda.file_dataset
WHERE dataset_id = '$id'
LIMIT 1
")

file_id=$(echo "$file_id" | awk '{$1=$1;print}')


kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT submission_file_path FROM sda.files
WHERE id = '$file_id'
"  |   cut -d'/' -f2 | awk 'NF' 

