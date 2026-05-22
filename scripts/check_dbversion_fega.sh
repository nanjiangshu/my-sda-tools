#!/bin/bash

set -e

# check db version for FEGA

kubectl -n fega-staging exec svc/fega-staging-sda-postgres-ro -c postgres -- psql -tA -U postgres -d sda -c "
SELECT version, description FROM sda.dbschema_version ORDER BY version DESC LIMIT 1;
" 