#!/bin/bash

# This script queries the file_event_log table in the sda database for a given file ID.
target="bp-prod"
file_id=""

usage="Usage: $0 [-target <target>] <file_id>
OPTIONS:
    -target <target>    Specify the target environment (default: bp-prod), can be one of:
                        fega-staging, fega-prod, bp-staging, bp-prod
"

# Parse command line arguments, it should report error if more than one positional argument is provided, and the order of the arguments should not matter
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
        service="svc/fega-staging-sda-postgres-ro"
        ;;
    fega-prod)
        namespace="fega-prod"
        service="svc/fega-prod-sda-postgres-ro"
        ;;
    bp-staging)
        namespace="sda-staging"
        service="svc/cnpg-sda-staging-ro"
        ;;
    bp-prod)
        namespace="sda-prod"
        service="svc/postgres-cluster-ro"
        ;;
    *)
        echo "Unknown target environment: $target"
        echo "$usage"
        exit 1
esac

# Check if a file_id was provided
if [ -z "$file_id" ]; then
    echo "$usage"
    exit 1
fi

# Remove leading/trailing whitespaces
file_id=$(echo "$file_id" | xargs)

kubectl -n $namespace exec $service -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.file_event_log
WHERE file_id = '$file_id'
ORDER BY started_at DESC
"
