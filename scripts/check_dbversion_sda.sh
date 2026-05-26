#!/bin/bash

set -e

# check db version for FEGA-staging FEGA-prod BP-staging and BP-prod
# usage: ./check_dbversion_sda.sh -target <target-environment>
# Example: ./check_dbversion_sda.sh -target fega-staging
usage="Usage: $0 -target <target-environment>
Example: $0 -target fega-staging"
if [ "$#" -lt 2 ] ; then
    echo "$usage"
    exit 1
fi
target=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) echo "Unknown argument: $1" ; echo "$usage" ; exit 1 ;;
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

kubectl -n $namespace exec $service -c postgres -- psql -tA -U postgres -d sda -c "
SELECT version, description FROM sda.dbschema_version ORDER BY version DESC LIMIT 1;
" 