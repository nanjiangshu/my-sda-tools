#!/bin/bash

infile="$1"

# Check if input file argument is provided
if [ -z "$infile" ]; then
    echo "Usage: $0 file_id_list_file"
    exit 1
fi

while IFS= read -r file_id; do
  info_verified=$(kubectl -n sda-prod exec svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -t -A -c "$(printf "INSERT INTO sda.file_event_log(file_id, event, correlation_id) VALUES('%s', 'verified', '%s');" "$file_id" "$file_id")" 2>/dev/null)

  # Check if psql or kubectl command failed
  if [ $? -ne 0 ] || [ -z "$info_verified" ]; then
    echo "Error executing psql for file_id: $file_id"
    continue # Skip to next file_id
  fi

  # Print the result
  echo "$info_verified"

done < "$infile"

