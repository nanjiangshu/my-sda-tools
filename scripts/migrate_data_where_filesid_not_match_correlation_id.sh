#!/bin/bash
set -e

DRY_RUN=false

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
        DRY_RUN=true
        shift
        ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo "========= DRY RUN MODE ========="
    echo "SQL commands will execute but will be ROLLED BACK at the end."
    ACTION_COMMAND="ROLLBACK;"
else
    echo "========= LIVE MIGRATION MODE ========="
    echo "WARNING: This will permanently modify production data."
    ACTION_COMMAND="COMMIT;"
fi

# Note the change to the '-rw' service endpoint
kubectl -n fega-staging exec -i svc/fega-staging-sda-postgres-rw -c postgres -- psql -U postgres -d sda << EOF
BEGIN;

-- 1. Show the work to be done (Helpful for dry-run verification)
SELECT f.id AS file_uuid, fel.id AS log_id, fel.file_id AS old_log_file_id, fel.correlation_id AS new_target_id
FROM sda.file_event_log AS fel
JOIN sda.files AS f ON f.id = fel.file_id
WHERE fel.file_id != fel.correlation_id AND fel.correlation_id IS NOT NULL;

-- 2. Update the parent files table first
UPDATE sda.files AS f
SET id = fel.correlation_id
FROM sda.file_event_log AS fel
WHERE f.id = fel.file_id
  AND fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- 3. Update the file_event_log table targeting exact log entries cleanly via PK (fel.id)
UPDATE sda.file_event_log AS f
SET file_id = fel.correlation_id
FROM sda.file_event_log AS fel
WHERE f.id = fel.id  -- Fixed the logic bug here! Joins on exact Log entry PK
  AND fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- Execute final commit or abort safety valve
$ACTION_COMMAND
EOF

if [ "$DRY_RUN" = true ]; then
    echo "========= DRY RUN COMPLETED CLEANLY (No changes saved) ========="
else
    echo "========= MIGRATION COMPLETED SUCCESSFULLY ========="
fi