# This script retrieves the folder path for a given dataset ID  
dataset_stableID=$1
if [ "$dataset_stableID" == "" ];then
    echo "Usage: $0 <dataset_stableID>"
    exit 1
fi


# ensure the output has no trailing white spaces at the beginning or end of each line
kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT stable_id FROM sda.files WHERE id IN (SELECT file_id FROM sda.file_dataset WHERE dataset_id = (SELECT id FROM sda.datasets WHERE stable_id = '$dataset_stableID'))
" | awk 'NF' | sort -u | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//'