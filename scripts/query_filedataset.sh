# This script queries the file_dataset table for a given dataset stable ID.
# It is used to find all files associated with a dataset. 
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

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.file_dataset
WHERE dataset_id = '$id'
"