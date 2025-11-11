#!/bin/bash
# This script queries the `sda.file_event_log` table for events related to file IDs provided in a file.
# It processes the file IDs in batches to avoid exceeding command line length limits.

# Check if file name is provided
if [ $# -eq 0 ]; then
  echo "No file provided."
  echo "Usage: $0 file [batch_size]"
  exit 1
fi

file=$1
batch_size=${2:-100}  # Set batch size to 2nd arg, with default of 100.
DB_APP_NAME=svc/postgres-cluster-r

# Check if file exists.
if [ ! -f "$file" ]; then
  echo "File not found: $file"
  exit 1
fi

file_ids=($(cat "$file"))  # Read file IDs into an array.
total=${#file_ids[@]}

for ((i=0; i<total; i+=batch_size)); do
  # Get a slice of the file IDs array.
  file_ids_slice=("${file_ids[@]:i:batch_size}")

  # convert array to string with each file_id quoted
  file_ids_str=$(printf "'%s'," "${file_ids_slice[@]}")
  file_ids_str=${file_ids_str%?}  # Remove trailing comma

  kubectl -n sda-prod exec $DB_APP_NAME -c postgres -- psql -U postgres -tA -d sda -c "
  WITH ordered_events AS (
      SELECT file_id, event 
      FROM sda.file_event_log
      WHERE file_id IN ($file_ids_str)
      ORDER BY file_id, started_at DESC
  )
  SELECT file_id, STRING_AGG(event, ',') 
  FROM ordered_events
  GROUP BY file_id
  "  
done
