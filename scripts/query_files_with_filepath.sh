#!/bin/bash
# This script queries the files table in the sda database for a specific filepath.

substring_match=false
no_header=false

usage="""
Usage: $0 [OPTIONS] <filepath>
Options:
  -h, --help          Show this help message and exit
  -s, --substring     Use substring match for filepath (default is exact match)
  -nh, --no-header    Do not include header in the output (default is to include header)
"""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "$usage"
            exit 0
            ;;
        -s|--substring)
            substring_match=true
            shift
            ;;
        -nh|--no-header)
            no_header=true
            shift
            ;;  
        *)
            filepath=$1
            shift
            ;;
    esac
done

if [ "$filepath" == "" ];then
    echo "$usage"
    exit 1
fi

if [ "$substring_match" = true ]; then
    filepath_condition="submission_file_path LIKE '%$filepath%'"
else
    filepath_condition="submission_file_path = '$filepath'"
fi
filepath=$(echo "$filepath" | xargs)

extra_options=""

if [ "$no_header" = true ]; then
    extra_options="-tA"
else
    extra_options="-t"
fi

# Query the files table for the specified filepath
kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql $extra_options -U postgres  -d sda -c "
SELECT * FROM sda.files
WHERE $filepath_condition 
"

