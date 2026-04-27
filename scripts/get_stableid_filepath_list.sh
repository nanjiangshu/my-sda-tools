#!/bin/bash
# This script get stable_id and filepath (without username) that will be
# provided to the submitter for a given dataset folder.

# usage: get_stableid_filepath_list.sh <dataset_folder> -check-disabled
# The output will be a tab-separated list of stable_id and filepath, with no header.
# Example output:
# stable_id1    path/to/file1
# stable_id2    path/to/file2
# ...

# when -check-disabled flag is provided, the script will exclude files that are
# marked as disabled in the file_event_log. This is determined by checking the
# most recent event for each file and excluding those where the latest event is
# 'disabled'.
# but this query can be slow, so it is optional to include the check for
# disabled files.

usage="Usage: $0 <dataset_folder> [-check-disabled]
This script retrieves stable IDs and file paths for files in a given dataset folder.
Options:
  -check-disabled   Exclude files that are marked as disabled in the file_event_log."

dataset_folder="$1"
check_disabled=false

# argument parsing
if [[ "$2" == "-check-disabled" ]]; then
    check_disabled=true
fi 

if [ "$dataset_folder" == "" ];then
    echo "$usage"
    exit 1
fi


if [ "$check_disabled" = true ]; then
  kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
  SELECT f.stable_id, f.submission_file_path 
  FROM sda.files f
  WHERE f.submission_file_path LIKE '%$dataset_folder/%'
    AND f.stable_id IS NOT NULL
  AND f.submission_file_path IS NOT NULL
  AND (
    SELECT event 
    FROM sda.file_event_log 
    WHERE file_id = f.id 
    ORDER BY started_at DESC, id DESC 
    LIMIT 1
  ) IS DISTINCT FROM 'disabled';
" | awk 'NF' | sort -u | tr '|' '\t'
else
  kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -tA -d sda -c "
  SELECT stable_id, submission_file_path FROM sda.files
  WHERE submission_file_path LIKE '%$dataset_folder/%'
  AND stable_id IS NOT NULL
  AND submission_file_path IS NOT NULL
  " | awk 'NF' | sort -u |  tr '|' '\t'
fi