#!/bin/bash
set -euo pipefail

DRY_RUN=false

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

kubectl -n fega-staging exec -i svc/fega-staging-sda-postgres-rw -c postgres -- \
psql -v ON_ERROR_STOP=1 -U postgres -d sda << EOF

BEGIN;

-- ====================================================================
-- Disable FK checks temporarily
-- ====================================================================

SET session_replication_role = replica;

-- ====================================================================
-- PRE-CHECKS
-- ====================================================================

SELECT '--- Scanning checksums table for affected file_ids ---' AS log_message;

SELECT
    c.file_id,
    COUNT(*)
FROM sda.checksums c
JOIN sda.file_event_log fel
    ON c.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL
GROUP BY c.file_id;

SELECT '--- Scanning file_dataset table for affected file_ids ---' AS log_message;

SELECT
    fd.file_id,
    COUNT(*)
FROM sda.file_dataset fd
JOIN sda.file_event_log fel
    ON fd.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL
GROUP BY fd.file_id;

SELECT '--- Scanning file_references table for affected file_ids ---' AS log_message;

SELECT
    fr.file_id,
    COUNT(*)
FROM sda.file_references fr
JOIN sda.file_event_log fel
    ON fr.file_id = fel.file_id
WHERE fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL
GROUP BY fr.file_id;

-- ====================================================================
-- SHOW TARGET ROWS
-- ====================================================================

SELECT '--- Rows to be fixed ---' AS log_message;

SELECT
    fel.id AS log_id,
    fel.file_id AS old_file_id,
    fel.correlation_id AS new_file_id
FROM sda.file_event_log fel
WHERE fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- ====================================================================
-- UPDATE FILES TABLE
-- ====================================================================

UPDATE sda.files f
SET id = fel.correlation_id
FROM sda.file_event_log fel
WHERE f.id = fel.file_id
  AND fel.file_id != fel.correlation_id
  AND fel.correlation_id IS NOT NULL;

-- ====================================================================
-- UPDATE FILE EVENT LOG
-- ====================================================================

UPDATE sda.file_event_log target
SET file_id = source.correlation_id
FROM sda.file_event_log source
WHERE target.id = source.id
  AND source.file_id != source.correlation_id
  AND source.correlation_id IS NOT NULL;

-- ====================================================================
-- Re-enable FK checks
-- ====================================================================

SET session_replication_role = DEFAULT;

-- ====================================================================
-- VALIDATION
-- ====================================================================

SELECT '--- Remaining mismatches ---' AS log_message;

SELECT COUNT(*) AS remaining_rows
FROM sda.file_event_log
WHERE file_id != correlation_id
  AND correlation_id IS NOT NULL;

SELECT '--- Broken file_event_log references ---' AS log_message;

SELECT COUNT(*) AS broken_refs
FROM sda.file_event_log fel
LEFT JOIN sda.files f
    ON f.id = fel.file_id
WHERE f.id IS NULL;

$ACTION_COMMAND

EOF

if [ "$DRY_RUN" = true ]; then
    echo "========= DRY RUN COMPLETED CLEANLY (No changes saved) ========="
else
    echo "========= MIGRATION COMPLETED SUCCESSFULLY ========="
fi