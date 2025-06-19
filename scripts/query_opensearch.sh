#!/bin/bash

# This script query opensearch

container_name="verify"
namespace="sda-prod"
datetime_left="2025-06-09T00:00:00Z"
# The default is now empty to allow the logic to work if no size is specified.
# OpenSearch will use its own default (usually 10) if the size parameter is omitted.
size="" 
match_string_in_log=""

# Fetching OpenSearch credentials from Vault
if [ "$OPENSEARCH_USER" != "" ];then
    guser=$OPENSEARCH_USER
else
    guser=$(vault kv get --field=admin-user  bp-secrets/cluster-bp-v2/opensearch)
fi

if [ "$OPENSEARCH_PASSWORD" != "" ];then
    gpass=$OPENSEARCH_PASSWORD
else
    gpass=$(vault kv get --field=admin-pass  bp-secrets/cluster-bp-v2/opensearch)
fi

usage="
Usage: $0 [OPTIONS] <match_string_in_log>
Options:
  -c, --container <container_name>   Specify the container name (default: $container_name)
  -n, --namespace <namespace>        Specify the namespace (default: $namespace)
  -d, --datetime <datetime_left>     Specify the datetime left in ISO format (default: $datetime_left)
  -s, --size <size>                  Specify the number of results to return (optional, OpenSearch default is 10)
  -h, --help                         Show this help message
"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--container) container_name="$2"; shift ;;
        -n|--namespace) namespace="$2"; shift ;;
        -d|--datetime) datetime_left="$2"; shift ;;
        -s|--size) size="$2"; shift ;;
        -h|--help) echo "$usage"; exit 0 ;;
        *) match_string_in_log="$1" ;;
    esac
    shift
done

if [ -z "$match_string_in_log" ]; then
    echo "Error: match_string_in_log is required."
    echo "$usage"
    exit 1
fi

# ==================== MODIFICATION START ====================

# 1. Build the base JSON payload
json_payload=$(cat <<EOF
{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "log": "$match_string_in_log"
          }
        },
        {
          "term": {
            "kubernetes.namespace_name.keyword": "$namespace"
          }
        },
        {
          "term": {
            "kubernetes.container_name.keyword": "$container_name"
          }
        },
        {
          "range": {
            "@timestamp": {
              "gte": "$datetime_left"
            }
          }
        }
      ]
    }
  }
EOF
)

# 2. Conditionally add the 'size' parameter if the variable is not empty
if [ "$size" != "" ]; then
    # Note the comma at the beginning to correctly append to the JSON object
    size_param=", \"size\": $size"
    # Append the size parameter just before the final closing brace
    json_payload="${json_payload}${size_param}"
fi

# 3. Add the final closing brace to the payload
json_payload="${json_payload} }"

# ==================== MODIFICATION END ====================


# 4. Use the dynamically built JSON payload in the curl command
curl -u "$guser:$gpass" -XGET "https://opensearch.bp-v2.bp.nbis.se/logstash-cluster-logs-*/_search" -H 'Content-Type: application/json' -d "$json_payload"