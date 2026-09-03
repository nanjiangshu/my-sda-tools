#!/usr/bin/env bash

# This script shows the event log for a given dataset ID.

usage="Usage: $0 <datasetID> [-target <target>]
Example: $0 aa-dataset-aaaaaa-bbbbbb -target bp-prod

-target <target> can be one of the following:
    fega-staging
    fega-prod
    bp-staging
    bp-prod
"

target="bp-prod"
datasetID=""
# in argument parsing, it should report error if the flag is wrong, and the
# order of the argument should not matter
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) datasetID="$1" ;;
    esac
    shift
done

if [ -z "${datasetID:-}" ]; then
    echo "$usage"
    exit 1
fi

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

kubectl -n $namespace exec $service -c postgres -- psql -U postgres -t -d sda -c "
SELECT * FROM sda.dataset_event_log
WHERE dataset_id = '$datasetID'
ORDER BY event_date DESC
"