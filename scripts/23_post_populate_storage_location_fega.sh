#!/bin/bash
set -euo pipefail

NAMESPACE="fega-staging"
DB_POD="svc/fega-staging-sda-postgres-rw"
DB_CONTAINER="postgres"
DB_NAME="sda"

# ENVs are INBOX_ENDPOINT, ARCHIVE_ENDPOINT, BACKUP_ENDPOINT
# and INBOX_BUCKET, ARCHIVE_BUCKET, BACKUP_BUCKET
# location is constructed as {endpoint}/{bucket}

INBOX_ENDPOINT="${INBOX_ENDPOINT:-}"
INBOX_BUCKET="${INBOX_BUCKET:-}"
if [[ -n "${INBOX_ENDPOINT}" && -n "${INBOX_BUCKET}" ]]; then
    INBOX_LOCATION="${INBOX_ENDPOINT}/${INBOX_BUCKET}"
else
    INBOX_LOCATION=""
fi

ARCHIVE_ENDPOINT="${ARCHIVE_ENDPOINT:-}"
ARCHIVE_BUCKET="${ARCHIVE_BUCKET:-}"
if [[ -n "${ARCHIVE_ENDPOINT}" && -n "${ARCHIVE_BUCKET}" ]]; then
    ARCHIVE_LOCATION="${ARCHIVE_ENDPOINT}/${ARCHIVE_BUCKET}"
else
    ARCHIVE_LOCATION=""
fi

BACKUP_ENDPOINT="${BACKUP_ENDPOINT:-}"
BACKUP_BUCKET="${BACKUP_BUCKET:-}"
if [[ -n "${BACKUP_ENDPOINT}" && -n "${BACKUP_BUCKET}" ]]; then
    BACKUP_LOCATION="${BACKUP_ENDPOINT}/${BACKUP_BUCKET}"
else
    BACKUP_LOCATION=""
fi

# Check if the required envs are set, if not, exit with error 
if [[ -z "${INBOX_LOCATION}" ]]; then
    echo "Error: INBOX_ENDPOINT and INBOX_BUCKET must be set"
    exit 1
fi
if [[ -z "${ARCHIVE_LOCATION}" ]]; then
    echo "Error: ARCHIVE_ENDPOINT and ARCHIVE_BUCKET must be set"
    exit 1
fi
if [[ -z "${BACKUP_LOCATION}" ]]; then
    echo "Warning: BACKUP_ENDPOINT and BACKUP_BUCKET are not set. Backup location will not be updated."
fi

# Print the values to be used in the migration for confirmation
echo "The following values will be used in the migration:"
echo "Inbox location:  ${INBOX_LOCATION}"
echo "Archive location: ${ARCHIVE_LOCATION}"
if [[ -n "${BACKUP_LOCATION}" ]]; then
    echo "Backup location:  ${BACKUP_LOCATION}"
else
    echo "Backup location:  (none)"
fi
echo "Please confirm to proceed with the migration."
read -rp "Type 'yes' to continue: " confirmation
if [[ "$confirmation" != "yes" ]]; then
    echo "Migration aborted by user."
    exit 0
fi

pause() {
    read -rp "Press ENTER to continue..."
}

run_sql() {
kubectl -n "${NAMESPACE}" exec -i "${DB_POD}" -c "${DB_CONTAINER}" -- \
psql -v ON_ERROR_STOP=1 -U postgres -d "${DB_NAME}" <<EOF
$1
EOF
}

echo "=================================================================="
echo "STEP 1 - VERIFY SCHEMA VERSION"
echo "=================================================================="

run_sql "
SELECT max(version) AS current_version
FROM sda.dbschema_version;
"

echo
echo "Verify manually that current_version = 23"
pause

echo "=================================================================="
echo "STEP 2 - PRE-MIGRATION COUNTS & CHECKS"
echo "=================================================================="

run_sql "
SELECT COUNT(*) AS total_files FROM sda.files;

SELECT COUNT(*) AS files_with_mismatched_uuids
FROM sda.file_event_log
WHERE file_id != correlation_id AND correlation_id IS NOT NULL;

SELECT COUNT(*) AS missing_submission_location
FROM sda.files
WHERE submission_location IS NULL;

SELECT COUNT(*) AS missing_archive_location
FROM sda.files
WHERE archive_location IS NULL
  AND archive_file_path != '';

SELECT COUNT(*) AS missing_backup_location
FROM sda.files
WHERE backup_location IS NULL
  AND backup_path != '';
"

pause

echo "=================================================================="
echo "STEP 3 & 4 - CORE TRANSACTION & VALIDATION PROMPT"
echo "=================================================================="
echo

# Prompt selection right before starting the active transaction sequence
echo "How should this core block execute at completion?"
echo "  [COMMIT]   - Save updates permanently to production."
echo "  [DRY-RUN]  - Execute everything normally but ROLLBACK changes at the end."
echo
read -rp "Type 'COMMIT' to proceed live, or press ENTER for safe DRY-RUN: " action_input

if [[ "$action_input" == "COMMIT" ]]; then
    FINAL_ACTION="COMMIT;"
    echo ">>> Running in LIVE MIGRATION MODE (Will permanent modify data)"
else
    FINAL_ACTION="ROLLBACK;"
    echo ">>> Running in DRY-RUN MODE (No modifications will be saved)"
fi
echo

kubectl -n "${NAMESPACE}" exec -i "${DB_POD}" -c "${DB_CONTAINER}" -- \
psql -v ON_ERROR_STOP=1 -U postgres -d "${DB_NAME}" <<EOF

BEGIN;

-- ================================================================
-- MIGRATION 20: Atomic Update for Mismatched Parent-Child IDs
-- ================================================================

WITH migrated_files AS (
    UPDATE sda.files AS f
    SET id = fel.correlation_id
    FROM sda.file_event_log AS fel
    WHERE f.id = fel.file_id
      AND fel.file_id != fel.correlation_id
      AND fel.correlation_id IS NOT NULL
    RETURNING f.id
)
UPDATE sda.file_event_log AS target_log
SET file_id = source_log.correlation_id
FROM sda.file_event_log AS source_log
WHERE target_log.id = source_log.id
  AND source_log.file_id != source_log.correlation_id
  AND source_log.correlation_id IS NOT NULL;

-- ================================================================
-- MIGRATION 23: S3 Storage Location & Path Assignments
-- ================================================================

-- Populate submission_location
UPDATE sda.files
SET submission_location = '${INBOX_LOCATION}'
WHERE submission_location IS NULL;

SELECT COUNT(*) AS updated_submission_locations
FROM sda.files
WHERE submission_location = '${INBOX_LOCATION}';

-- Populate archive_location
UPDATE sda.files
SET archive_location = '${ARCHIVE_LOCATION}'
WHERE archive_file_path != ''
  AND archive_location IS NULL;

SELECT COUNT(*) AS updated_archive_locations
FROM sda.files
WHERE archive_location = '${ARCHIVE_LOCATION}';

-- Populate backup_path
UPDATE sda.files
SET backup_path = archive_file_path
WHERE archive_file_path != ''
  AND backup_path IS NULL;

SELECT COUNT(*) AS updated_backup_paths
FROM sda.files
WHERE backup_path IS NOT NULL;

-- Execute final action choice determined by your prompt selection
$FINAL_ACTION

EOF

pause

# ====================================================================
# STEP 4.5 - CONDITIONAL BACKUP LOCATION MIGRATION
# ====================================================================
if [[ -n "${BACKUP_LOCATION}" ]]; then

    echo "=================================================================="
    echo "STEP 4.5 - POPULATING OPTIONAL BACKUP STORAGE LOCATION"
    echo "=================================================================="

    kubectl -n "${NAMESPACE}" exec -i "${DB_POD}" -c "${DB_CONTAINER}" -- \
    psql -v ON_ERROR_STOP=1 -U postgres -d "${DB_NAME}" <<EOF
    BEGIN;

    UPDATE sda.files
    SET backup_location = '${BACKUP_LOCATION}'
    WHERE backup_path != ''
      AND backup_location IS NULL;

    SELECT COUNT(*) AS updated_backup_locations
    FROM sda.files
    WHERE backup_location = '${BACKUP_LOCATION}';

    -- Conditional blocks commit directly if chosen or match transaction type
    $FINAL_ACTION
EOF

    pause
fi

echo "=================================================================="
echo "STEP 5 - FINAL VERIFICATION"
echo "=================================================================="

run_sql "
SELECT COUNT(*) AS remaining_mismatched_uuids
FROM sda.file_event_log
WHERE file_id != correlation_id AND correlation_id IS NOT NULL;

SELECT COUNT(*) AS missing_submission_location
FROM sda.files
WHERE submission_location IS NULL;

SELECT COUNT(*) AS missing_archive_location
FROM sda.files
WHERE archive_location IS NULL
  AND archive_file_path != '';

SELECT COUNT(*) AS missing_backup_location
FROM sda.files
WHERE backup_location IS NULL
  AND backup_path != '';

SELECT COUNT(*) AS inconsistent_backup_state
FROM sda.files
WHERE backup_location IS NOT NULL
  AND backup_path IS NULL;

SELECT COUNT(*) AS inconsistent_archive_state
FROM sda.files
WHERE archive_location IS NOT NULL
  AND archive_file_path = '';
"

echo
echo "Migration completed."