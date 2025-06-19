#!/bin/bash

# This script re-verifies datasets in BigPicture using the admin-API.
# It requires the dataset IDs as arguments and uses the access token from s3cmd-bp.conf

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <datasetID1> <datasetID2> ..."
    exit 1
fi

datasetIDList="$@"

API_HOST="https://api.bp.nbis.se"
ACCESS_TOKEN=$(grep access_token s3cmd-bp.conf  | awk '{print $NF}')

echo $datasetIDList

for datasetID in $datasetIDList; do
    datetime=$(date)
    echo
    echo "####### Reverify dataset $datasetID : $datetime #####"
    curl -v -H "Authorization: Bearer $ACCESS_TOKEN" -X PUT $API_HOST/dataset/verify/${datasetID} 
done
