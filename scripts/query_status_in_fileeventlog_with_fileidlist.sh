#!/bin/bash
# This script queries the `sda.file_event_log` table for events related to file IDs provided in a file.
# It processes the file IDs in batches to avoid exceeding command line length limits.

# Check if file name is provided
usage="
Usage: $0 -i file -o outfile [-b batch_size]
options:
  -i file        Input file containing file IDs
  -o outfile     Output file to write results
  -b batch_size  Number of file IDs to process per batch (default: 3200)
"

batch_size=${batch_size:-3200}  # Set default batch size if not provided.

if [ $# -eq 0 ]; then
  echo "No file provided."
  echo "$usage"
  exit 1
fi

while getopts "i:o:b:" opt; do
  case $opt in
    i) file="$OPTARG" ;;
    o) outfile="$OPTARG" ;;
    b) batch_size="$OPTARG" ;;
    *) echo "$usage"; exit 1 ;;
  esac
done




if [[ -z "$file" || -z "$outfile" ]]; then
  echo "Error: Missing required arguments."
  echo "$usage"
  exit 1
fi
DB_APP_NAME=svc/postgres-cluster-ro

# Check if file exists.
if [ ! -f "$file" ]; then
  echo "File not found: $file"
  exit 1
fi

file_ids=($(cat "$file"))  # Read file IDs into an array.
total=${#file_ids[@]}

# write result to outfile

(
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
) > "$outfile"  # Append all results to the output file.
