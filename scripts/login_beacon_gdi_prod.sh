#!/bin/bash

# This script login to the mongodb for the GDI deployment 
set -euo pipefail

MONGO_INITDB_ROOT_USERNAME=$(kubectl -n gdi-prod get secret mongodb-admin-af-beacon -o jsonpath="{.data.username}" | base64 --decode)
MONGO_INITDB_ROOT_PASSWORD=$(kubectl -n gdi-prod get secret mongodb-admin-af-beacon -o jsonpath="{.data.password}" | base64 --decode)

kubectl -n gdi-prod exec -it mongodb-0 -- mongosh \
  -u $MONGO_INITDB_ROOT_USERNAME \
  -p $MONGO_INITDB_ROOT_PASSWORD \
  --authenticationDatabase admin \
  beacon