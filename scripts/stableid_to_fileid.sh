#!/bin/bash
set -euo pipefail

usage="Usage: $0 [-l <stableid_file_list>] [stableid ...] [-target <target-environment>]
Example: $0 aa-File-aaaaaa-bbbbbb -target fega-staging"

if [ "$#" -lt 1 ] ; then
    echo "$usage"
    exit 1
fi

target="bp-prod"
stableid_file_list=""
stableids=()

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
    fega-staging) namespace="fega-staging"; service="svc/fega-staging-sda-postgres-ro" ;;
    fega-prod)    namespace="fega-prod";    service="svc/fega-prod-sda-postgres-ro" ;;
    bp-staging)   namespace="sda-staging";  service="svc/cnpg-sda-staging-ro" ;;
    bp-prod)      namespace="sda-prod";     service="svc/postgres-cluster-ro" ;;
    *) echo "Unknown target environment: $target"; echo "$usage"; exit 1 ;;
esac

# Create temporary file for input IDs
tmp_ids=$(mktemp)
trap 'rm -f "$tmp_ids"' EXIT

# Fast trimming and file loading
if [ ! -z "${stableid_file_list:-}" ]; then
    awk 'NF {gsub(/^[ \t]+|[ \t]+$/, ""); print}' "$stableid_file_list" >> "$tmp_ids"
fi

if [ "${#stableids[@]}" -gt 0 ]; then
    printf "%s\n" "${stableids[@]}" | awk 'NF {gsub(/^[ \t]+|[ \t]+$/, ""); print}' >> "$tmp_ids"
fi

if [ ! -s "$tmp_ids" ]; then
    echo "No stableids provided."
    echo "$usage"
    exit 1
fi

# Convert clean lines into batch SQL queries (1000 IDs per batch) piped into psql via stdin (-i)
awk '
BEGIN { count=0 }
NF {
    gsub(/\x27/, "\x27\x27"); # Escape single quotes
    if (count == 0) printf "SELECT id FROM sda.files WHERE stable_id IN (\x27%s\x27", $0;
    else printf ",\x27%s\x27", $0;
    count++;
    if (count == 1000) {
        printf ");\n";
        count=0;
    }
}
END {
    if (count > 0) printf ");\n";
}
' "$tmp_ids" | kubectl -n "$namespace" exec -i "$service" -c postgres -- \
psql -U postgres -t -d sda | awk 'NF' | sort -u | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//'