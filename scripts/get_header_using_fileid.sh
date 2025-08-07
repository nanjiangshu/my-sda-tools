#!/bin/bash
# This script retrieves the header of the archived file from the sda.files table based on fileid. 


usage="""
Usage: $0 [OPTIONS] <filepath>
Options:
  -h, --help          Show this help message and exit
"""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "$usage"
            exit 0
            ;;
        *)
            fileid=$1
            shift
            ;;
    esac
done

if [ "$fileid" == "" ];then
    echo "$usage"
    exit 1
fi

# Query the files table for the specified fileid
kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -tA -U postgres  -d sda -c "
SELECT header FROM sda.files
WHERE fileid = '$fileid'
"
