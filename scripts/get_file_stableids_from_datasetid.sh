# This script retrieves the folder path for a given dataset ID  
dataset_stableID=$1
if [ "$dataset_stableID" == "" ];then
    echo "Usage: $0 <dataset_stableID>"
    exit 1
fi


kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT stable_id FROM sda.files WHERE id IN (SELECT file_id FROM sda.file_dataset WHERE dataset_id = (SELECT id FROM sda.datasets WHERE stable_id = '$dataset_stableID'))
" | awk 'NF' | sort -u 
