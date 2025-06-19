
if [ $# -lt 1 ];then
    echo "usage: $0 datasetIDs"
    exit 1
fi

datasetIDList=$*

rundir=/data3/project-sda/sda-cli/tmp

(for datasetID in $datasetIDList; do
dataset_folder=$(bash $rundir/get_datasetfolder_from_datasetid.sh  $datasetID  | awk 'NF')
username=$(bash $rundir/get_user_from_datasetid.sh  $datasetID  | awk 'NF')
numFile=$(bash $rundir/query_filedataset.sh $datasetID | grep -ve '^\s*$' | wc -l)
numRecordInDatasetEventLog=$( bash $rundir/query_dataseteventlog.sh  $datasetID |grep -ve '^\s*$' |  wc -l)
echo "$datasetID" "$dataset_folder" "$numFile" "$numRecordInDatasetEventLog" "$username"
done) | sort -k3,3g
