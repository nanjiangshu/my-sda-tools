#!/bin/bash
set -euo pipefail

# This script adds an event to the file_event_log table in the sda database for a given file ID and event type.

target="bp-prod"
file_id=""
event_type=""

usage="Usage: $0 [-target <target>] <file_id> <event_type>
OPTIONS:
    -target <target>    Specify the target environment (default: bp-prod), can be one of:
                        fega-staging, fega-prod, bp-staging, bp-prod
"

# Parse command line arguments, distinguishing between options and positional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -target)
            target="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "$usage"
            exit 1
            ;;
        *)
            if [ -z "${file_id:-}" ]; then
                file_id="$1"
            elif [ -z "${event_type:-}" ]; then
                event_type="$1"
            else
                echo "Unexpected argument: $1"
                echo "$usage"
                exit 1
            fi
            shift
            ;;
    esac
done

case $target in
    fega-staging)
        namespace="fega-staging"
        service="svc/fega-staging-sda-postgres-rw"
        ;;
    fega-prod)
        namespace="fega-prod"
        service="svc/fega-prod-sda-postgres-rw"
        ;;
    bp-staging)
        namespace="sda-staging"
        service="svc/cnpg-sda-staging-rw"
        ;;
    bp-prod)
        namespace="sda-prod"
        service="svc/postgres-cluster-rw"
        ;;
    *)
        echo "Unknown target environment: $target"
        echo "$usage"
        exit 1
esac

if [ -z "$file_id" ] || [ -z "$event_type" ]; then
    echo "$usage"
    exit 1
fi


if [ -z "$file_id" ]; then
    echo "Error: file_id is required."
    echo "$usage"
    exit 1
fi
if [ -z "$event_type" ]; then
    echo "Error: event_type is required."
    echo "$usage"
    exit 1
fi

# 1. Basic validation: Ensure UUID looks like a UUID to prevent SQL injection
if [[ ! $file_id =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "Error: Invalid UUID format."
    exit 1
fi

echo "Logging event '$event_type' for file: $file_id"

# 2. Use a Heredoc to pass the SQL. This is cleaner and handles quotes better.
# 3. We capture the output to verify if an insert actually happened.
RESULT=$(kubectl -n "$namespace" exec -i "$service" -c postgres -- psql -U postgres -d sda -t -q <<EOF
INSERT INTO sda.file_event_log (file_id, event, user_id, message)
SELECT id, '$event_type', 'manual', json_build_object('user', submission_user, 'filepath', submission_file_path)
FROM sda.files
WHERE id = '$file_id'
RETURNING file_id;
EOF
)

# 4. Check if the RESULT is empty (meaning the SELECT found no file)
if [ -z "$(echo "$RESULT" | tr -d '[:space:]')" ]; then
    echo "Error: No file found with UUID $file_id. No log entry created."
    exit 1
else
    echo "Log entry successfully created for file $file_id."
fi