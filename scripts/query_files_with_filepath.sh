filepath=$1

if [ "$filepath" == "" ];then
    exit 1
fi

kubectl -n sda-prod exec svc/postgres-cluster-ro -c postgres -- psql -U postgres  -d sda -c "
SELECT * FROM sda.files
WHERE submission_file_path = '$filepath'
"

