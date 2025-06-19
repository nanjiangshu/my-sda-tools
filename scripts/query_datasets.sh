# This script shows the datasets info for a given dataset stable ID.
dataset_stableID=$1
if [ "$dataset_stableID" == "" ];then
    echo "Usage: $0 <dataset_stableID>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.datasets
WHERE stable_id = '$dataset_stableID'
ORDER BY created_at DESC
"