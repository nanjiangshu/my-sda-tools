#!/bin/bash

# This script query opensearch

container_name="verify"
namespace="sda-prod"
# The default is now empty to allow the logic to work if no size is specified.
# OpenSearch will use its own default (usually 10) if the size parameter is omitted.
size="" 

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
Query OpenSearch logs after a specific datetime.

Usage: $0 [OPTIONS] datetime_left

Options:
  -c, --container <container_name>   Specify the container name (default: $container_name)
  -n, --namespace <namespace>        Specify the namespace (default: $namespace)
  -s, --size <size>                  Specify the number of results to return (optional, OpenSearch default is 10)
  -h, --help                         Show this help message
"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--container) container_name="$2"; shift ;;
        -n|--namespace) namespace="$2"; shift ;;
        -s|--size) size="$2"; shift ;;
        -h|--help) echo "$usage"; exit 0 ;;
        *) datetime_left="$1" ;;
    esac
    shift
done

if [ -z "$datetime_left" ]; then
    echo "Error: datetime_left is required."
    echo "$usage"
    exit 1
fi

# 1. Build the base JSON payload
json_payload=$(cat <<EOF
{
  "query": {
    "bool": {
      "must": [
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
  },
  "sort": [
    {
      "@timestamp": "asc"
    }
  ],
  "search_after": [
    "$datetime_left"
  ]  
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


# 4. Use the dynamically built JSON payload in the curl command
curl -u "$guser:$gpass" -XGET "https://opensearch.bp-v2.bp.nbis.se/logstash-cluster-logs-*/_search" -H 'Content-Type: application/json' -d "$json_payload"