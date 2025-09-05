#!/bin/bash

# This script retrieves the list of files from the S3inbox for a dataset folder.

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
s3cmdFile=../s3cmd-bp-master-inbox.conf
s3cmdFile=$(realpath "$s3cmdFile")
server=prod

dataset_folder=$1
user_underscore=

Usage="""
Usage: $0 [OPTIONS] <dataset_folder> [-u <user>]
Options:
    -h, --help   Show this help message and exit
    -u, --user   Specify the user (default: bp)
    -s3cmd, --s3cmd       Specify the s3cmd config file (default: ../s3cmd-bp-master-inbox.conf)
    -server, --server     Specify the server (default: prod)
"""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "$Usage"
            exit 0
            ;;
        -u|--user)
            user_underscore="$2"
            shift 2
            ;;
        -s3cmd|--s3cmd)
            s3cmdFile="$2"
            shift 2
            ;;
        -server|--server)
            server="$2"
            shift 2
            ;;
        *)
            dataset_folder=$1
            shift
            ;;
    esac
done


if [ -z "$dataset_folder" ]; then
    echo "Error: Dataset folder is required."
    exit 1
fi

if [ "$server" != "prod" && "$server" != "staging" ]; then
    echo "Error: Invalid server specified. Must be one of: prod, staging"
    exit 1
fi

if [ ! -f "$s3cmdFile" ]; then
    echo "Error: s3cmd config file $s3cmdFile does not exist."
    exit 1
fi

bucket=inbox-2024-01

if [ "$server" == "prod" ]; then
    bucket=inbox-2024-01
elif [ "$server" == "staging" ]; then
    bucket=staging-2024-01
fi

if [ -z "$user_underscore" ]; then
    s3cmd -c $s3cmdFile  ls s3://$bucket --recursive | grep $dataset_folder > $dataset_folder.filelist.txt
else
    s3cmd -c $s3cmdFile  ls s3://$bucket/$user_underscore/$dataset_folder --recursive | grep $dataset_folder > $dataset_folder.filelist.txt
fi

wc -l $dataset_folder.filelist.txt | awk '{print "Number of files: " $1}'
echo "File list saved to: $dataset_folder.filelist.txt"
