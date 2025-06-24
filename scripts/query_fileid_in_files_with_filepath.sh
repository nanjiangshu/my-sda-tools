#!/bin/bash
# This script get file_id in the files table in the sda database for a specific filepath.

substring_match=false

usage="""
Usage: $0 [OPTIONS] <filepath>
Options:
  -h, --help          Show this help message and exit
  -s, --substring     Use substring match for filepath (default is exact match)
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

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -tA -U postgres  -d sda -c "
SELECT id FROM sda.files
WHERE $filepath_condition 
"

