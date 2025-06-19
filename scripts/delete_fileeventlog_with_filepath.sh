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

# delete the last file_event_log entry for the given file_id and event_type
kubectl -n sda-prod exec svc/postgres-cluster-rw -c postgres -- psql -U postgres -t -d sda -c "
DELETE FROM sda.file_event_log
WHERE id = (
  SELECT id
  FROM sda.file_event_log
  WHERE file_id = '$file_id' AND event = '$event_type'
  ORDER BY started_at DESC
  LIMIT 1
)"