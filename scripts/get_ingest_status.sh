#!/bin/bash
# this script checks the file status statistics

set -euo pipefail

SCRIPT_DIR=$(dirname "$0")
binpath=$(realpath "$SCRIPT_DIR")

usage="""
Usage: $0 <user> <dataset_folder> <outdir>
<user> : the LSAAI user ID
<dataset_folder> : the dataset folder name
<outdir> : directory to save intermediate and final results
"""

if [ $# -ne 3 ]; then
  echo "$usage"
  exit 1
fi

user="$1"
dataset_folder="$2"
outdir="$3"

if [ ! -d "$outdir" ]; then
  mkdir -p "$outdir"
fi

bash $binpath/query_userfiles.sh $user $dataset_folder > $outdir/$dataset_folder.userfiles.txt

awk -F\| '{print $1}'  $outdir/$dataset_folder.userfiles.txt  | sort -u > $outdir/$dataset_folder.fileidlist.txt

bash $binpath/query_status_in_fileeventlog_with_fileidlist.sh $outdir/$dataset_folder.fileidlist.txt  > $outdir/$dataset_folder.status.list.txt

awk -F\| '{print $2}' $outdir/$dataset_folder.status.list.txt | awk -F, '{print $1}' | sort | uniq -c
