#!/bin/bash
# This script test the running speed of two SQL queries
# It also output the results to a file so that we can compare the results later


RunOldQuery() {
    local user="$1"
    kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -tA -U postgres -d sda -c "
    SELECT f.id, f.submission_file_path, e.event, f.created_at 
    FROM sda.files f
    LEFT JOIN (
        SELECT DISTINCT ON (file_id) file_id, started_at, event FROM sda.file_event_log ORDER BY file_id, started_at DESC
    ) e ON f.id = e.file_id 
    WHERE f.submission_user = '$user'
    AND f.id NOT IN (
        SELECT f.id
        FROM sda.files f
        RIGHT JOIN sda.file_dataset d ON f.id = d.file_id
    );
    " | sort -u > tmp/"${user}"_oldQuery.txt
}

RunNewQuery() {
    local user="$1"
    kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -tA -U postgres -d sda -c "
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
    WHERE f.submission_user = '$user'
    AND d.file_id IS NULL;
    " | sort -u > tmp/"${user}"_newQuery.txt
}   

userListFile="$1"
if [ -z "$userListFile" ]; then
    echo "Usage: $0 user_list_file"
    exit 1
fi

userList=$(cat "$userListFile")

for user in $userList; do
    echo "Running query for user: $user"

    start=$(date +%s%3N)
    RunOldQuery "$user"
    end=$(date +%s%3N)
    echo "RunOldQuery took $((end - start)) ms"

    start=$(date +%s%3N)
    RunNewQuery "$user"
    end=$(date +%s%3N)
    echo "RunNewQuery took $((end - start)) ms"

    if ! diff "tmp/${user}_oldQuery.txt" "tmp/${user}_newQuery.txt" > /dev/null; then
        echo "Differences found for user: $user"
    fi

    num_lines_old=$(wc -l < tmp/"${user}"_oldQuery.txt)
    num_lines_new=$(wc -l < tmp/"${user}"_newQuery.txt)

    echo "Old query line count: $num_lines_old"
    echo "New query line count: $num_lines_new"

    echo
done