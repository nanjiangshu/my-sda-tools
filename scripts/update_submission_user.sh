#!/bin/bash

# Default values
DRY_RUN=false
FILE_LIST=""
OLD_USER=""
NEW_USER=""
NAMESPACE="sda-prod"
SVC="svc/postgres-cluster-rw"

usage() {
    echo "Usage: $0 -file-id-list <file> -old-user <id> -new-user <id> [-dry-run]"
    echo ""
    echo "Options:"
    echo "  -file-id-list    Path to file containing UUIDs (one per line)"
    echo "  -old-user        The current submission_user value"
    echo "  -new-user        The new submission_user value"
    echo "  -dry-run         Show what would happen without executing the update"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -file-id-list) FILE_LIST="$2"; shift ;;
        -old-user) OLD_USER="$2"; shift ;;
        -new-user) NEW_USER="$2"; shift ;;
        -dry-run) DRY_RUN=true ;;
        *) usage ;;
    esac
    shift
done

# Validate inputs
if [[ -z "$FILE_LIST" || ! -f "$FILE_LIST" ]]; then
    echo "Error: File list not found."
    usage
fi

if [[ -z "$OLD_USER" || -z "$NEW_USER" ]]; then
    echo "Error: Both old-user and new-user must be specified."
    usage
fi

if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN MODE: No changes will be committed ---"
    
    # In dry run, we perform a SELECT join instead of an UPDATE
    cat "$FILE_LIST" | kubectl -n "$NAMESPACE" exec -i "$SVC" -c postgres -- psql -U postgres -d sda -c "
        CREATE TEMP TABLE update_batch (f_id UUID);
        COPY update_batch FROM STDIN;
        
        SELECT id, stable_id, submission_user as current_user, '$NEW_USER' as target_user
        FROM sda.files
        JOIN update_batch ON sda.files.id = update_batch.f_id
        WHERE sda.files.submission_user = '$OLD_USER';
    "
    echo "--- End of Dry Run ---"
else
    echo "Updating submission_user from $OLD_USER to $NEW_USER..."
    
    cat "$FILE_LIST" | kubectl -n "$NAMESPACE" exec -i "$SVC" -c postgres -- psql -U postgres -d sda -c "
        BEGIN;
        CREATE TEMP TABLE update_batch (f_id UUID);
        COPY update_batch FROM STDIN;

        UPDATE sda.files
        SET 
            submission_user = '$NEW_USER',
            last_modified = clock_timestamp(),
            last_modified_by = CURRENT_USER
        FROM update_batch
        WHERE sda.files.id = update_batch.f_id
        AND sda.files.submission_user = '$OLD_USER';

        -- Verify count before committing
        COMMIT;
    "
    echo "Update complete."
fi