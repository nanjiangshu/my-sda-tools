#!/bin/bash
set -euo pipefail
# This script queries the checksums table in the sda database for a given file UUID.

# add an option to select the target
# e.g. fega-staging or bp-staging or bp-prod
# for fega-staging, namespace is fega-staging and the service is svc/fega-staging-sda-postgres-ro
# for fega-prod, name space is fega-prod and the service is svc/fega-prod-sda-postgres-ro
# for bp-staging, namespace is bp-staging and the service is svc/cnpg-sda-staging-ro
# for bp-prod, namespace is bp-prod and the service is svc/postgres-cluster-ro

# note that the target option is optional and defaults to bp-prod if not provided

usage="Usage: $0 <file-uuid> [-target <target-environment>]
Example: $0 123e4567-e89b-12d3-a456-426614174000 -target fega-staging"

# argument parsing
if [ "$#" -lt 1 ] ; then
    echo "$usage"
    exit 1
fi

target="bp-prod"
# in argument parsing, it should report error if the flag is wrong, and the
# order of the argument should not matter
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) file_uuid="$1" ;;
    esac
    shift
done

if [ -z "${file_uuid:-}" ]; then
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

kubectl -n "$namespace" exec "$service" -c postgres -- \
psql -U postgres -t -d sda -c "
SELECT *
FROM sda.checksums
WHERE file_id = '$file_uuid'
"