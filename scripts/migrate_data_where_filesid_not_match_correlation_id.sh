#!/bin/bash
set -euo pipefail

# This script migrates data in the sda database where file_id does not match correlation_id in the file_event_log table.
# It updates the files table and file_event_log table to set file_id to correlation_id where they do not match, and correlation_id is not null.
# The script also includes pre-checks to show how many rows will be affected in the checksums, file_dataset and file_references tables, and shows the target rows to be fixed before performing the update.
# The script can be run in dry-run mode where it will execute the SQL commands but roll back at the end, allowing you to see the changes that would be made without actually modifying the data.

# the target can be FEGA-staging FEGA-prod BP-staging and BP-prod
# usage: ./migrate_data_where_filesid_not_match_correlation_id.sh -target <target-environment>
# Example: ./migrate_data_where_filesid_not_match_correlation_id.sh -target fega-staging

DRY_RUN=false
target=""

usage="Usage: $0 -target <target-environment> [--dry-run]
Example: $0 -target fega-staging --dry-run"
if [ "$#" -lt 2 ] ; then
    echo "$usage"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        -*) echo "Unknown option: $1" ; echo "$usage" ; exit 1 ;;
        *) echo "Unknown argument: $1" ; echo "$usage" ; exit 1 ;;
    esac
    shift
done

case $target in
    fega-staging)
        namespace="fega-staging"
        service="svc/fega-staging-sda-postgres-ro"
        ;;
    fega-prod)
        namespace="fega-prod"
        service="svc/fega-prod-sda-postgres-ro"
        ;;
    bp-staging)
        namespace="sda-staging"
        service="svc/cnpg-sda-staging-ro"
        ;;
    bp-prod)
        namespace="sda-prod"
        service="svc/postgres-cluster-ro"
        ;;
    *)
        echo "Unknown target environment: $target"
        echo "$usage"
        exit 1
esac

# check db version before running the migration, if db versin is > 19, exit, since this migration is only meant to be run on db version 19 or below
echo "Checking database version for target environment: $target"
db_version=$(kubectl -n $namespace exec $service -c postgres -- psql -tA -U postgres -d sda -c "
SELECT version FROM sda.dbschema_version ORDER BY version DESC LIMIT 1;
")
echo "Database version: $db_version"
if [ "$db_version" -gt 19 ]; then
    echo "Database version is greater than 19. Migration cannot proceed."
    exit 1
fi


if [ "$DRY_RUN" = true ]; then
    echo "========= DRY RUN MODE ========="
    echo "SQL commands will execute but will be ROLLED BACK at the end."
    ACTION_COMMAND="ROLLBACK;"
else
    echo "========= LIVE MIGRATION MODE ========="
    echo "WARNING: This will permanently modify production data."
    ACTION_COMMAND="COMMIT;"
fi

kubectl -n $namespace exec -i $service -c postgres -- \
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