#!/bin/bash
# This script deletes the last entry in the `sda.file_event_log` table for a given file ID and event type.
# Usage: ./delete_fileeventlog_with_fileid.sh <fileid> <event_type>

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo
    echo "Usage: $0 <fileid> <event_type>"
    exit 1
fi

file_id="$1"
event_type="$2"

# Remove leading/trailing whitespaces
file_id=$(echo "$file_id" | xargs)
event_type=$(echo "$event_type" | xargs)


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