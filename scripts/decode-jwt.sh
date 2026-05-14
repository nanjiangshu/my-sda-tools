#!/bin/bash

# This script decode JWT token using base64 and jq

# usage: ./decode-jwt.sh <jwt-token>
# On mac, it should use gbase64 instead of base64
# detect the platform and use the appropriate base64 command
if [[ "$OSTYPE" == "darwin"* ]]; then
    base64_cmd="gbase64"
else
    base64_cmd="base64"
fi 

usage="Usage: $0 <jwt-token>"
if [ "$#" -ne 1 ]; then
    echo "$usage"
    exit 1
fi
jwt_token="$1"
# Split the JWT token into its three parts
IFS='.' read -r header payload signature <<< "$jwt_token"
# Decode the header and payload from base64
header_decoded=$(echo "$header" | $base64_cmd --decode 2>/dev/null)
payload_decoded=$(echo "$payload" | $base64_cmd --decode 2>/dev/null)
# Check if the decoding was successful
if [ -z "$header_decoded" ] || [ -z "$payload_decoded" ]; then
    echo "Invalid JWT token"
    exit 1
fi
# Print the decoded header and payload in a readable format
echo "Header:"
echo "$header_decoded" | jq .
echo "Payload:"
echo "$payload_decoded" | jq .

