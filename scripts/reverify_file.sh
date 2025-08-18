#!/bin/bash

# This script re-verifies files in BigPicture using the admin-API. 
# It requires the accession IDs as arguments and uses the access token from s3cmd-bp.conf

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <accessionID1> <accessionID2> ..."
    exit 1
fi

accessionIDList="$@"

API_HOST="https://api.bp.nbis.se"
ACCESS_TOKEN=$(grep access_token s3cmd-bp.conf  | awk '{print $NF}')

echo "Number of accession IDs to reverify: $(echo $accessionIDList | wc -w)" 

for accessionID in $accessionIDList; do
    datetime=$(date)
    echo
    echo "####### Reverify file $accessionID : $datetime #####"
    curl -v -H "Authorization: Bearer $ACCESS_TOKEN" -X PUT $API_HOST/file/verify/${accessionID} 
done
