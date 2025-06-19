# This script adds a new file_event_log entry for a given file path and event type.
if [ "$#" -ne 2 ]; then
    echo
    echo "Usage: $0 <filepath> <event_type>"
    exit 1
fi

filepath=$1
event_type=$2

file_id=$(kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT file_id FROM sda.file_event_log 
WHERE message->>'filepath' LIKE '%"$filepath"%'
LIMIT 1
")

file_id=$(echo "$file_id" | awk '{$1=$1;print}')

# add a new file_event_log entry for the given file_id and event_type 
kubectl -n sda-prod exec svc/postgres-cluster-rw -c postgres -- psql -U postgres -t -d sda -c "
INSERT INTO sda.file_event_log(file_id, event, correlation_id) VALUES('$file_id', '$event_type', '$file_id')
"
