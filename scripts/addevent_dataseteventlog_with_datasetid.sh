#!/bin/bash
set -euo pipefail

# This script adds an event to the sda.dataset_event_log table in the sda database for a given dataset_id

target="bp-prod"
dataset_id=""
event_type=""

usage="Usage: $0 [-target <target>] <dataset_id> <event_type>
OPTIONS:
    -target <target>    Specify the target environment (default: bp-prod), can be one of:
                        fega-staging, fega-prod, bp-staging, bp-prod
"

# Parse command line arguments, distinguishing between options and positional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -target)
            if [[ $# -lt 2 ]]; then echo "Error: -target requires an argument"; exit 1; fi
            target="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "$usage"
            exit 1
            ;;
        *)
            if [ -z "${dataset_id:-}" ]; then
                dataset_id="$1"
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


if [ -z "$dataset_id" ]; then
    echo "Error: dataset_id is required."
    echo "$usage"
    exit 1
fi
if [ -z "$event_type" ]; then
    echo "Error: event_type is required."
    echo "$usage"
    exit 1
fi

# Validate the dataset_id format (e.g., aa-Dataset-xxxxxx-xxxxxx)
if [[ ! $dataset_id =~ ^aa-[dD]ataset-[0-9a-zA-Z]{6}-[0-9a-zA-Z]{6}$ ]]; then
    echo "Error: Invalid dataset_id format for '$dataset_id'. Expected format: aa-Dataset-xxxxxx-xxxxxx"
    exit 1
fi

echo "Logging event '$event_type' for dataset: $dataset_id"

# insert the deprecated event should be like this
# INSERT INTO sda.dataset_event_log (dataset_id, event, message, event_date)
# VALUES (
#     'aa-dataset-xbdnsr-uvx2zq',
#     'deprecated',
#     '{\"reason\": \"Dataset removal requested by submitter\"}'::jsonb,
#     clock_timestamp()
# );

# 2. Use a Heredoc to pass the SQL. This is cleaner and handles quotes better.
# 3. We capture the output to verify if an insert actually happened.
kubectl -n "$namespace" exec -i "$service" -c postgres -- psql -U postgres -d sda -t -q <<EOF
INSERT INTO sda.dataset_event_log (dataset_id, event, message, event_date)
VALUES (
    '$dataset_id',
    '$event_type',
    '{}',
    clock_timestamp()
);
EOF

# 4. Check if the insert was successful by querying the count of rows with the given dataset_id and event_type
RESULT=$(kubectl -n "$namespace" exec -i "$service" -c postgres -- psql -U postgres -d sda -t -q <<EOF
SELECT COUNT(*) FROM sda.dataset_event_log WHERE dataset_id = '$dataset_id' AND event = '$event_type';
EOF
)

COUNT=$(echo "$RESULT" | tr -d '[:space:]')
if [[ "$COUNT" -eq 0 ]]; then
    echo "Error: Failed to log event..."
    exit 1
else
    echo "Log entry successfully created for dataset $dataset_id with event '$event_type'."
fi