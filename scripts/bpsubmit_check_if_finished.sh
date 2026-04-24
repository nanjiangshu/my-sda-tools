#!/bin/bash

# This script checks if the dataset has been fully ingested by the big
# picture pipeline. It checks if all files are mapped to the dataset, and if all
# mapped files are synced to the s3 bucket.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
binpath="$SCRIPT_DIR" 
S3CMD_CONFIG="$HOME/.sda/s3cmd-allas.conf"

# == pre-requisites ==

current_folder_name=$(basename "$PWD")
if [[ "$current_folder_name" != "$DATASET_FOLDER" ]]; then
    echo "Error: Current directory '$current_folder_name' does not match expected dataset folder '$DATASET_FOLDER'. Please navigate to the correct directory and try again."
    exit 1
fi

if [[ -z "$DATASET_ID" || -z "$USER_ID" || -z "$DATASET_FOLDER" ]]; then
    echo "Error: One or more required environment variables (DATASET_ID, USER_ID, DATASET_FOLDER) are not set."
    exit 1
fi

# check if s3cmd config file exists
if [[ ! -f "$S3CMD_CONFIG" ]]; then
    echo "Error: s3cmd config file not found at $S3CMD_CONFIG"
    exit 1
fi

# == main process ==
echo -e "DATASET_ID:\t$DATASET_ID"
echo -e "USER_ID:\t$USER_ID"
echo -e "DATASET_FOLDER:\t$DATASET_FOLDER"

# check if all files are mapped to the dataset
bash $binpath/get_file_stableids_from_datasetid.sh $DATASET_ID > $DATASET_FOLDER.mapped_stableids.txt

mkdir -p data
if [ ! -s data/${DATASET_FOLDER}-stableIDs.txt ] ; then
    bash $binpath/get_stableid_filepath_list.sh $DATASET_FOLDER > data/${DATASET_FOLDER}-stableIDs.txt  
fi

numFileTotal=$(cat data/${DATASET_FOLDER}-stableIDs.txt | wc -l)


if [ ! -f "$DATASET_FOLDER.filelist.txt" ];then 
    user_underscore=$(echo $USER_ID | tr '@' '_')
    bash $binpath/get_filelist_for_datasetfolder.sh -u $user_underscore $DATASET_FOLDER
fi
numFileInbox=$(cat $DATASET_FOLDER.filelist.txt | wc -l)

numMapped=$(cat $DATASET_FOLDER.mapped_stableids.txt | wc -l)

# check if all files are synced
numSynced=$(s3cmd -c $S3CMD_CONFIG ls -r s3://bigpicture-202603/$DATASET_FOLDER  | wc -l)

echo -e "NumFileTotal:\t$numFileTotal"
echo -e "NumFileInbox:\t$numFileInbox"
echo -e "NumMapped:\t$numMapped"
echo -e "NumSynced:\t$numSynced"

# check if mapped stable ids are the same as those in the file ${DATASET_FOLDER}-stableIDs.txt
suffix=$RANDOM
cat $DATASET_FOLDER.mapped_stableids.txt | sort -u > /tmp/check_bp_map_1_$suffix.txt
awk '{print $1}' data/${DATASET_FOLDER}-stableIDs.txt | sort -u > /tmp/check_bp_map_2_$suffix.txt

if ! diff -q /tmp/check_bp_map_1_$suffix.txt /tmp/check_bp_map_2_$suffix.txt  > /dev/null; then
    echo "stable ids in $DATASET_FOLDER.mapped_stableids.txt and ${DATASET_FOLDER}-stableIDs.txt differ"
fi

rm -f /tmp/check_bp_map_[12]_$suffix.txt
