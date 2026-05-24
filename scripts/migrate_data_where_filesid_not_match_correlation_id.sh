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

kubectl -n fega-staging exec -i svc/fega-staging-sda-postgres-rw -c postgres -- psql -U postgres -d sda << EOF
BEGIN;

-- ====================================================================
-- PRE-CHECK: Scan dependent tables for the affected file_ids
-- ====================================================================
SELECT '--- Scanning checksums table for affected file_ids ---' AS log_message;
SELECT 'checksums' AS source_table, c.file_id, COUNT(*)
FROM sda.checksums c
JOIN sda.file_event_log fel ON c.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id AND fel.correlation_id IS NOT NULL
GROUP BY c.file_id;

SELECT '--- Scanning file_dataset table for affected file_ids ---' AS log_message;
SELECT 'file_dataset' AS source_table, fd.file_id, COUNT(*)
FROM sda.file_dataset fd
JOIN sda.file_event_log fel ON fd.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id AND fel.correlation_id IS NOT NULL
GROUP BY fd.file_id;

SELECT '--- Scanning file_references table for affected file_ids ---' AS log_message;
SELECT 'file_references' AS source_table, fr.file_id, COUNT(*)
FROM sda.file_references fr
JOIN sda.file_event_log fel ON fr.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id AND fel.correlation_id IS NOT NULL
GROUP BY fr.file_id;

-- ====================================================================
-- MIGRATION EXECUTION
-- ====================================================================

-- Make the foreign key constraint deferrable so we can shift IDs in tandem
ALTER TABLE sda.file_event_log
  ALTER CONSTRAINT file_event_log_file_id_fkey DEFERRABLE INITIALLY DEFERRED;

SELECT '--- Scanning core log mismatch records ---' AS log_message;
-- 1. Show the main log mismatch records
SELECT f.id AS file_uuid, fel.id AS log_id, fel.file_id AS old_log_file_id, fel.correlation_id AS new_target_id
FROM sda.file_event_log AS fel
JOIN sda.files AS f ON f.id = fel.file_id
WHERE fel.file_id != fel.correlation_id AND fel.correlation_id IS NOT NULL;

-- 2. Update parent files table
UPDATE sda.files AS f
SET id = fel.correlation_id
FROM sda.file_event_log AS fel
WHERE f.id = fel.file_id
  AND fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- 3. Update child file_event_log entries cleanly via PK
UPDATE sda.file_event_log AS f
SET file_id = fel.correlation_id
FROM sda.file_event_log AS fel
WHERE f.id = fel.id
  AND fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- Restore normal constraint state before wrapping up
ALTER TABLE sda.file_event_log
  ALTER CONSTRAINT file_event_log_file_id_fkey NOT DEFERRABLE;

$ACTION_COMMAND
EOF

if [ "$DRY_RUN" = true ]; then
    echo "========= DRY RUN COMPLETED CLEANLY (No changes saved) ========="
else
    echo "========= MIGRATION COMPLETED SUCCESSFULLY ========="
fi