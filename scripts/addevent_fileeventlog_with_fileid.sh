#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <fileUUID> <event_type>"
    exit 1
fi

fileUUID=$1
event_type=$2

# 1. Basic validation: Ensure UUID looks like a UUID to prevent SQL injection
if [[ ! $fileUUID =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "Error: Invalid UUID format."
    exit 1
fi

echo "Logging event '$event_type' for file: $fileUUID"

# 2. Use a Heredoc to pass the SQL. This is cleaner and handles quotes better.
# 3. We capture the output to verify if an insert actually happened.
RESULT=$(kubectl -n sda-prod exec -i svc/postgres-cluster-rw -c postgres -- psql -U postgres -d sda -t -q <<EOF
INSERT INTO sda.file_event_log (file_id, event, user_id, message)
SELECT id, '$event_type', 'manual', json_build_object('user', submission_user, 'filepath', submission_file_path)
FROM sda.files
WHERE id = '$fileUUID'
RETURNING file_id;
EOF
)

# 4. Check if the RESULT is empty (meaning the SELECT found no file)
if [ -z "$(echo "$RESULT" | tr -d '[:space:]')" ]; then
    echo "Error: No file found with UUID $fileUUID. No log entry created."
    exit 1
else
    echo "Log entry successfully created for file $fileUUID."
fi