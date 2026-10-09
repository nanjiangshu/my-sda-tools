#!/bin/bash
# This script retrieves list of files given a user_id and optionally a dataset_folder, using different query methods based on the -m option.
usage="""
Usage: $0 -u <user_id> [-d <dataset_folder>] [-dbapp <db_app_name>]
Options:
  -dbapp <db_app_name>   Specify the database app name to use with kubectl. Default is svc/postgres-cluster-ro.
  -u <user_id>           Specify the user ID to query.
  -d <dataset_folder>    Specify the dataset folder to filter by. Optional.
  -m <method>            Specify the query method to use. Optional. Valid values
                         are 'old', 'new', 'new_improved', 'new_improved2', 'new_improved3', 'branch'
                         (default is 'new_improved4').
"""

DB_APP_NAME=svc/postgres-cluster-ro
method="new_improved4"

if [ "$#" -lt 1 ]; then
    echo "$usage"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u)
            user_id="$2"
            shift 2
            ;;
        -d)
            dataset_folder="$2"
            shift 2
            ;;
        -dbapp)
            DB_APP_NAME="$2"
            shift 2
            ;;
        -m)
            method="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "$usage"
            exit 1
            ;;
    esac
done

if [ -z "$user_id" ]; then
    echo "Error: user_id is required."
    echo "$usage"
    exit 1
fi


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
	where submission_file_path like '$dataset_folder%' AND submission_user='$user_id' )
	order by file_id, id desc
)

select le.file_id, f.submission_file_path, f.stable_id, le.event, f.created_at from last_entries le
left join sda.files f on f.id=le.file_id
AND NOT EXISTS (SELECT 1 FROM sda.file_dataset d WHERE f.id = d.file_id);
    "
}

RunNewQueryImproved2() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec "$DB_APP_NAME" -c postgres -- psql -tA -U postgres -d sda -c "
SELECT
    f.id AS file_id,
    f.submission_file_path,
    f.stable_id,
    le.event,
    f.created_at
FROM sda.files f
CROSS JOIN LATERAL (
    SELECT event
    FROM sda.file_event_log
    WHERE file_id = f.id
    ORDER BY id DESC
    LIMIT 1
) le
WHERE f.submission_user = '$user_id'
  AND f.submission_file_path LIKE '$dataset_folder%'
  AND NOT EXISTS (
      SELECT 1 FROM sda.file_dataset d WHERE f.id = d.file_id
  );
"
}

RunNewQueryImproved3() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec "$DB_APP_NAME" -c postgres -- psql -tA -U postgres -d sda -c "
    -- EXPLAIN ANALYZE
WITH filtered_files AS (
    SELECT f.id, f.submission_file_path, f.stable_id, f.created_at
    FROM sda.files f
    WHERE f.submission_user = '$user_id'
      AND f.submission_file_path LIKE '$dataset_folder%'
      AND NOT EXISTS (
          SELECT 1 FROM sda.file_dataset d WHERE d.file_id = f.id
      )
)
SELECT
    ff.id AS file_id,
    ff.submission_file_path,
    ff.stable_id,
    le.event,
    ff.created_at
FROM filtered_files ff
CROSS JOIN LATERAL (
    SELECT event
    FROM sda.file_event_log
    WHERE file_id = ff.id
    ORDER BY id DESC
    LIMIT 1
) le;
"
}

RunNewQueryImproved4() {
    local user_id="$1"
    local dataset_folder="$2"
    kubectl -n sda-prod exec "$DB_APP_NAME" -c postgres -- psql -tA -U postgres -d sda -c "
    -- EXPLAIN ANALYZE
WITH filtered_files AS (
    SELECT f.id, f.submission_file_path, f.stable_id, f.created_at
    FROM sda.files f
    WHERE f.submission_user = '$user_id'
      AND f.submission_file_path LIKE '$dataset_folder%'
      AND NOT EXISTS (
          SELECT 1 FROM sda.file_dataset d WHERE d.file_id = f.id
      )
)
SELECT
    ff.id AS file_id,
    ff.submission_file_path,
    ff.stable_id,
    le.event,
    ff.created_at
FROM filtered_files ff
CROSS JOIN LATERAL (
    SELECT event
    FROM sda.file_event_log
    WHERE file_id = ff.id
    ORDER BY started_at DESC
    LIMIT 1
) le;
"
}


RunPr2665_1Query() {
    local user_id="$1"
    local dataset_folder="$2"
    # Same query as GetUserFiles on feat/improve-userfile-query-performance, without the
    # page limit. The values are passed as psql variables (:'user', :'folder'), which psql
    # quotes, so quotes or '_' in the folder name are handled correctly.
    kubectl -n sda-prod exec -i "$DB_APP_NAME" -c postgres -- \
        psql -tA -U postgres -d sda -v user="$user_id" -v folder="$dataset_folder" <<'SQL'
SELECT f.id, f.submission_file_path, f.stable_id, COALESCE(f.last_event, '') AS event, f.created_at
FROM sda.files AS f
    LEFT JOIN sda.file_dataset AS fd ON fd.file_id = f.id
WHERE f.submission_user = :'user'
    AND f.submission_file_path COLLATE "C" >= :'folder'
    AND f.submission_file_path COLLATE "C" < :'folder' || chr(1114111)
    AND fd.file_id IS NULL AND COALESCE(f.last_event, '') NOT IN ('disabled', 'removed')
ORDER BY f.id ASC;
SQL
}

RunV402Query() {
    local user_id="$1"
    local dataset_folder="$2"
    # Same query as GetUserFiles in v4.0.2 (before the index fix), without the page limit.
    # Like the API, an empty folder becomes NULL (no prefix filter), and the prefix
    # length is passed in bytes (octet_length), the same as Go's len().
    kubectl -n sda-prod exec -i "$DB_APP_NAME" -c postgres -- \
        psql -tA -U postgres -d sda -v user="$user_id" -v folder="$dataset_folder" <<'SQL'
SELECT f.id, f.submission_file_path, f.stable_id, COALESCE(f.last_event, '') AS event, f.created_at
FROM sda.files AS f
    LEFT JOIN sda.file_dataset AS fd ON fd.file_id = f.id
WHERE f.submission_user = :'user'
    AND (NULLIF(:'folder', '') IS NULL
         OR substr(f.submission_file_path, 1, octet_length(:'folder')) = NULLIF(:'folder', ''))
    AND fd.file_id IS NULL AND COALESCE(f.last_event, '') NOT IN ('disabled', 'removed')
ORDER BY f.id ASC;
SQL
}

RunPR2665_2Query() {
    local user_id="$1"
    local dataset_folder="$2"
    local page_limit="${PAGE_LIMIT:-1000}"              # API default page size; 0 = all rows in one page
    local plan_mode="${PLAN_MODE:-force_generic_plan}"  # what the API's prepared statement settles on
    # Exact GetUserFiles queries from fix/improve-userfile-query-performance (commit 2bc8afbf+),
    # run as prepared statements with the API's argument order: $1 user, $2 cursor, $3 limit, $4 prefix.
    # Pages like the API: fetch limit+1, print limit, next cursor = last printed id; the first page
    # uses the nil UUID. Per-page timings go to stderr.
    kubectl -n sda-prod exec -i "$DB_APP_NAME" -c postgres -- \
        bash -s -- "$user_id" "$dataset_folder" "$page_limit" "$plan_mode" <<'EOF'
user="$1"; folder="$2"; limit="$3"; plan_mode="$4"
cursor=00000000-0000-0000-0000-000000000000
fetch=$(( limit > 0 ? limit + 1 : 2147483647 ))
page=0
while :; do
    page=$((page + 1))
    start=$(date +%s%N)
    if [ -z "$folder" ]; then
        rows=$(psql -qtA -U postgres -d sda -v user="$user" -v cursor="$cursor" -v fetch="$fetch" -v plan_mode="$plan_mode" <<'SQL'
SET plan_cache_mode = :plan_mode;
PREPARE getUserFiles(text, uuid, int) AS
SELECT f.id, f.submission_file_path, f.stable_id, COALESCE(f.last_event, '') as event, f.created_at, f.submission_file_size
FROM sda.files AS f
	LEFT JOIN sda.file_dataset AS fd ON fd.file_id = f.id
 WHERE f.submission_user = $1
	AND fd.file_id IS NULL AND COALESCE(f.last_event, '') NOT IN ('disabled', 'removed')
	AND f.id > $2::UUID
ORDER BY f.id ASC LIMIT $3;
EXECUTE getUserFiles(:'user', :'cursor', :fetch);
SQL
)
    else
        rows=$(psql -qtA -U postgres -d sda -v user="$user" -v cursor="$cursor" -v fetch="$fetch" -v folder="$folder" -v plan_mode="$plan_mode" <<'SQL'
SET plan_cache_mode = :plan_mode;
PREPARE getUserFilesByPathPrefix(text, uuid, int, text) AS
SELECT f.id, f.submission_file_path, f.stable_id, COALESCE(f.last_event, '') as event, f.created_at, f.submission_file_size
FROM sda.files AS f
	LEFT JOIN sda.file_dataset AS fd ON fd.file_id = f.id
 WHERE f.submission_user = $1
	AND f.submission_file_path COLLATE "C" >= $4::TEXT
	AND f.submission_file_path COLLATE "C" < $4::TEXT || chr(1114111)
	AND fd.file_id IS NULL AND COALESCE(f.last_event, '') NOT IN ('disabled', 'removed')
	AND f.id > $2::UUID
ORDER BY f.id ASC LIMIT $3;
EXECUTE getUserFilesByPathPrefix(:'user', :'cursor', :fetch, :'folder');
SQL
)
    fi
    n=$( [ -z "$rows" ] && echo 0 || printf '%s\n' "$rows" | wc -l )
    more=0
    if [ "$limit" -gt 0 ] && [ "$n" -gt "$limit" ]; then
        rows=$(printf '%s\n' "$rows" | head -n "$limit"); n=$limit; more=1
    fi
    [ -n "$rows" ] && printf '%s\n' "$rows"
    echo "page $page: $n rows, $(( ($(date +%s%N) - start) / 1000000 )) ms" >&2
    [ "$more" = 1 ] || break
    cursor=$(printf '%s\n' "$rows" | tail -n 1 | cut -d'|' -f1)
done
EOF
}



case "$method" in
    v4.0.2)
        RunV402Query "$user_id" "${dataset_folder}"
        ;;
    old)
        RunOldQuery "$user_id" "${dataset_folder}"
        ;;
    new)
        RunNewQuery "$user_id" "${dataset_folder}"
        ;;
    new_improved)
        RunNewQueryImproved "$user_id" "${dataset_folder}"
        ;;
    new_improved2)
        RunNewQueryImproved2 "$user_id" "${dataset_folder}"
        ;;
    new_improved3)
        RunNewQueryImproved3 "$user_id" "${dataset_folder}"
        ;;
    new_improved4)
        RunNewQueryImproved4 "$user_id" "${dataset_folder}"
        ;;
    pr2665_1|branch)
        RunPr2665_1Query "$user_id" "${dataset_folder}"
        ;;
    pr2665_2)
        RunPr2665_2Query "$user_id" "${dataset_folder}"
        ;;
    *)
        echo "Unknown method: $method"
        exit 1
        ;;
esac
