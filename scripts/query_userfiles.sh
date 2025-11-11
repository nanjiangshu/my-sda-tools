#!/bin/bash
# This script retrieves list of files give user_id and optionally dataset_folder 

usage="""
Usage: $0 <user_id> [<dataset_folder>]
"""

if [ "$#" -lt 1 ]; then
    echo "$usage"
    exit 1
fi
user_id="$1"
dataset_folder="${2:-}"
if [ -z "$user_id" ]; then
    echo "Error: user_id is required."
    echo "$usage"
    exit 1
fi

DB_APP_NAME=svc/postgres-cluster-r 

RunOldQuery() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec $DB_APP_NAME -c postgres -- psql -tA -U postgres -d sda -c "
    SELECT f.id, f.submission_file_path, e.event, f.created_at 
    FROM sda.files f
    LEFT JOIN (
        SELECT DISTINCT ON (file_id) file_id, started_at, event FROM sda.file_event_log ORDER BY file_id, started_at DESC
    ) e ON f.id = e.file_id 
    WHERE f.submission_user = '$user_id'
    AND f.id NOT IN (
        SELECT f.id
        FROM sda.files f
        RIGHT JOIN sda.file_dataset d ON f.id = d.file_id
    );
    " | sort -u  | grep "${dataset_folder:-.*}" 
}

RunNewQuery() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec $DB_APP_NAME -c postgres -- psql -tA -U postgres -d sda -c "
    SELECT f.id, 
           f.submission_file_path, 
           file_events.event, 
           f.created_at 
    FROM sda.files f
    LEFT JOIN (
        SELECT file_id, 
               MAX(started_at) AS max_started_at 
        FROM sda.file_event_log 
        GROUP BY file_id
    ) AS max_file_events ON f.id = max_file_events.file_id 
    LEFT JOIN sda.file_event_log AS file_events ON file_events.file_id = max_file_events.file_id 
                                                  AND file_events.started_at = max_file_events.max_started_at
    LEFT JOIN sda.file_dataset d ON f.id = d.file_id   
    WHERE f.submission_user = '$user_id'
    AND d.file_id IS NULL;
    " | sort -u | grep "${dataset_folder:-.*}" 
}

RunNewQueryImproved() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec $DB_APP_NAME -c postgres -- psql -tA -U postgres -d sda -c "
with last_entries as (
	select distinct on (file_id) * from sda.file_event_log
	where file_id in (select id from sda.files 
	where submission_file_path like '%$dataset_folder%' AND submission_user='$user_id' )
	order by file_id, id desc
)

select le.file_id, f.submission_file_path, f.stable_id, le.event, f.created_at from last_entries le 
left join sda.files f on f.id=le.file_id
AND NOT EXISTS (SELECT 1 FROM sda.file_dataset d WHERE f.id = d.file_id);
    "  
}



RunNewQueryImproved "$user_id" "${dataset_folder}"
