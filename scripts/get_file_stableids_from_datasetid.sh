#!/bin/bash

# This script retrieves the file stable IDs for a given dataset ID

set -e -x
usage="Usage: $0 -target <target-environment>

    -target <target-environment> : Specify the target environment (fega-staging, fega-prod, bp-staging, bp-prod)
    <dataset_stableID> : The stable ID of the dataset for which to retrieve file stable IDs

Example: $0 -target fega-staging <dataset_stableID>
"

target=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) dataset_stableID="$1" ; shift ;;
    esac
    shift
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


# ensure the output has no trailing white spaces at the beginning or end of each line
kubectl -n $namespace exec $service -c postgres -- psql -U postgres -t -d sda -c "
SELECT stable_id FROM sda.files WHERE id IN (SELECT file_id FROM sda.file_dataset WHERE dataset_id = (SELECT id FROM sda.datasets WHERE stable_id = '$dataset_stableID'))
" | awk 'NF' | sort -u | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//'