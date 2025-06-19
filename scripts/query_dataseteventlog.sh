# This script shows the event log for a given dataset ID.
datasetID=$1
if [ "$datasetID" == "" ];then
    echo "Usage: $0 <datasetID>"
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.dataset_event_log
WHERE dataset_id = '$datasetID'
ORDER BY event_date DESC
"