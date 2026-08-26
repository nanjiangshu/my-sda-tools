#!/bin/bash
set -euo pipefail
# This script retrieve the file UUID for given stable ids

# add an option to select the target
# e.g. fega-staging or bp-staging or bp-prod
# for fega-staging, namespace is fega-staging and the service is svc/fega-staging-sda-postgres-ro
# for fega-prod, name space is fega-prod and the service is svc/fega-prod-sda-postgres-ro
# for bp-staging, namespace is sda-staging and the service is svc/cnpg-sda-staging-ro
# for bp-prod, namespace is sda-prod and the service is svc/postgres-cluster-ro

# note that the target option is optional and defaults to bp-prod if not provided

usage="Usage: $0 -l <stableid_file_list> stableid [stableid ...] [-target <target-environment>]
Example: $0  aa-File-aaaaaa-bbbbbb -target fega-staging"

# argument parsing
if [ "$#" -lt 1 ] ; then
    echo "$usage"
    exit 1
fi

target="bp-prod"
stableid_file_list=""
stableids=()
# in argument parsing, it should report error if the flag is wrong, and the
# order of the argument should not matter
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -l) stableid_file_list="$2"; shift ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) stableids+=("$1") ;;
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

if [ ! -z "${stableid_file_list:-}" ]; then
    # read stableids from the file and append to the stableids array
    while IFS= read -r line; do
        # trim the white space before appending to stableids array
        stableids+=("$(echo "$line" | xargs)")
    done < "$stableid_file_list"
fi

number_of_stableids=${#stableids[@]}
if [ "$number_of_stableids" -eq 0 ]; then
    echo "No stableids provided."
    echo "$usage"
    exit 1
fi

# echo "Number of stableids to process: $number_of_stableids"

# 1. Read file lines into a formatted single-quoted, comma-separated string
#    Example output: 'id1','id2','id3'
formatted_ids=$(printf "'%s'," "${stableids[@]}")
formatted_ids=${formatted_ids%,}

# 2. Execute psql safely
kubectl -n "$namespace" exec "$service" -c postgres -- \
psql -U postgres -t -d sda -c \
"SELECT id FROM sda.files WHERE stable_id IN ($formatted_ids);" | awk 'NF' | sort -u | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//'