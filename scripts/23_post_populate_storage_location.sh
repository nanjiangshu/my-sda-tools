#!/bin/bash
set -euo pipefail

# This script is a post-migration script to populate the submission_location,
# archive_location and backup_location columns in the files table for FEGA
# environments after the migration in version 23. The script will check the
# current db schema version before running the migration, and will only proceed
# if the version is 23. The script will also prompt the user to confirm the
# values to be used in the migration, and will show the counts of affected rows
# before and after the migration for verification. The script can be run in
# dry-run mode where it will execute the SQL commands but roll back at the end,
# allowing you to see the changes that would be made without actually modifying
# the data.  The target can be fega-staging, fega-prod, bp-staging and bp-prod
# The procedure is interactive and includes multiple confirmation prompts to
# ensure the user is aware of the changes being made.

target=""
inbox_endpoint=""
inbox_bucket=""
archive_endpoint=""
archive_bucket=""
backup_endpoint=""
backup_bucket=""
DB_CONTAINER="postgres"
DB_NAME="sda"

usage="
Usage: $0 -target <target-environment> 
      -inbox-endpoint <inbox-endpoint>
      -inbox-bucket <inbox-bucket>
      -archive-endpoint <archive-endpoint>
      -archive-bucket <archive-bucket>
      [-backup-endpoint <backup-endpoint>]
      [-backup-bucket <backup-bucket>]

target-environment: fega-staging, fega-prod, bp-staging, bp-prod"

if [ "$#" -lt 2 ] ; then
    echo "$usage"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -target) target="$2"; shift ;;
        -inbox-endpoint) inbox_endpoint="$2"; shift ;;
        -inbox-bucket) inbox_bucket="$2"; shift ;;
        -archive-endpoint) archive_endpoint="$2"; shift ;;
        -archive-bucket) archive_bucket="$2"; shift ;;
        -backup-endpoint) backup_endpoint="$2"; shift ;;
        -backup-bucket) backup_bucket="$2"; shift ;;
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


# check db version before running the migration, if db versin != 23, exit, since this migration is only meant to be run on db version 23
echo "Checking database version for target environment: $target"
db_version=$(kubectl -n $namespace exec $service -c $DB_CONTAINER -- psql -tA -U postgres -d $DB_NAME -c "
SELECT version FROM sda.dbschema_version ORDER BY version DESC LIMIT 1;
")
echo "Database version: $db_version"
if [ "$db_version" -ne 23 ]; then
    echo "Database version is not 23. Migration cannot proceed."
    exit 1
fi

# location is constructed as {endpoint}/{bucket}

if [[ -n "${inbox_endpoint}" && -n "${inbox_bucket}" ]]; then
    inbox_location="${inbox_endpoint}/${inbox_bucket}"
else
    inbox_location=""
fi

if [[ -n "${archive_endpoint}" && -n "${archive_bucket}" ]]; then
    archive_location="${archive_endpoint}/${archive_bucket}"
else
    archive_location=""
fi

if [[ -n "${backup_endpoint}" && -n "${backup_bucket}" ]]; then
    backup_location="${backup_endpoint}/${backup_bucket}"
else
    backup_location=""
fi


# check if the required envs are set, if not, exit with error 
if [[ -z "${inbox_location}" ]]; then
    echo "Error: INBOX_ENDPOINT and INBOX_BUCKET must be set"
    exit 1
fi
if [[ -z "${archive_location}" ]]; then
    echo "Error: ARCHIVE_ENDPOINT and ARCHIVE_BUCKET must be set"
    exit 1
fi
if [[ -z "${backup_location}" ]]; then
    echo "Warning: BACKUP_ENDPOINT and BACKUP_BUCKET are not set. Backup location will not be updated."
fi


# print the values to be used in the migration for confirmation
echo "The following values will be used in the migration:"
echo "Inbox location: ${inbox_location}"
echo "Archive location: ${archive_location}"
if [[ -n "${backup_location}" ]]; then
    echo "Backup location: ${backup_location}"
else
    echo "Backup location: (none)"
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
kubectl -n "${namespace}" exec -i "${service}" -c "${DB_CONTAINER}" -- \
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
echo "STEP 2 - PRE-MIGRATION COUNTS"
echo "=================================================================="

run_sql "
SELECT COUNT(*) AS total_files FROM sda.files;

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
echo "PROMPT - SELECTION EXECUTION ACTION FOR STEP 3"
echo "=================================================================="
echo "How should the following transaction block execute at completion?"
echo "  [COMMIT]   - Save updates permanently to production."
echo "  [DRY-RUN]  - Execute everything normally but ROLLBACK changes at the end."
echo
read -rp "Type 'COMMIT' to save live changes, or press ENTER for a safe DRY-RUN: " action_input

if [[ "$action_input" == "COMMIT" ]]; then
    FINAL_ACTION="COMMIT;"
    echo ">>> Action Confirmed: Script will run a LIVE COMMIT."
else
    FINAL_ACTION="ROLLBACK;"
    echo ">>> Action Confirmed: Script will run a DRY-RUN (Changes will be discarded)."
fi
echo

echo "=================================================================="
echo "STEP 3 - EXECUTE TRANSACTION"
echo "=================================================================="

kubectl -n "${namespace}" exec -i "${service}" -c "${DB_CONTAINER}" -- \
psql -v ON_ERROR_STOP=1 -U postgres -d "${DB_NAME}" <<EOF

BEGIN;

-- ================================================================
-- Preview rows before updates
-- ================================================================

SELECT COUNT(*) AS files_missing_submission_location
FROM sda.files
WHERE submission_location IS NULL;

SELECT COUNT(*) AS files_missing_archive_location
FROM sda.files
WHERE archive_location IS NULL
  AND archive_file_path != '';

-- ================================================================
-- Populate submission_location
-- ================================================================

UPDATE sda.files
SET submission_location = '${inbox_location}'
WHERE submission_location IS NULL;

SELECT COUNT(*) AS updated_submission_locations
FROM sda.files
WHERE submission_location = '${inbox_location}';

-- ================================================================
-- Populate archive_location
-- ================================================================

UPDATE sda.files
SET archive_location = '${archive_location}'
WHERE archive_file_path != ''
  AND archive_location IS NULL;

SELECT COUNT(*) AS updated_archive_locations
FROM sda.files
WHERE archive_location = '${archive_location}';

-- ================================================================
-- Populate backup_path
-- ================================================================

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

echo
echo "=================================================================="
echo "STEP 4 - MANUAL VALIDATION PAUSE"
echo "=================================================================="
echo "The main migration transaction block has completed executing."
echo "Review the log messages printed above to verify accuracy."
echo
pause

if [[ -n "${backup_location}" ]]; then

echo "=================================================================="
echo "STEP 4.5 - POPULATING OPTIONAL BACKUP STORAGE LOCATION"
echo "=================================================================="

kubectl -n "${namespace}" exec -i "${service}" -c "${DB_CONTAINER}" -- \
psql -v ON_ERROR_STOP=1 -U postgres -d "${DB_NAME}" <<EOF

BEGIN;

UPDATE sda.files
SET backup_location = '${backup_location}'
WHERE backup_path != ''
  AND backup_location IS NULL;

SELECT COUNT(*) AS updated_backup_locations
FROM sda.files
WHERE backup_location = '${backup_location}';

-- Matches the same execution scope chosen in the main prompt
$FINAL_ACTION

EOF

fi

echo "=================================================================="
echo "STEP 5 - FINAL VERIFICATION"
echo "=================================================================="

run_sql "
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