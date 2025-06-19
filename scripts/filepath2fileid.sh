filepath=$1

if [ "$filepath" == "" ];then
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres -t -d sda -c "
SELECT file_id FROM sda.file_event_log 
WHERE message->>'filepath' LIKE '%"$filepath"%'
LIMIT 1
"
