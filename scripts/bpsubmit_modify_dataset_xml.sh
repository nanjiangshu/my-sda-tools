#!/bin/bash
set -euo pipefail

# this function modifies the dataset.xml file by adding an accession attribute
# to the DATASET element and encrypting it using crypt4gh, then uploads it to
# the specified S3 bucket
# It use the dataset_id provided in the argument

usage="Usage: $0 [-dry-run] -dataset-folder <dataset_folder> -dataset-id <dataset_id> -user-id <user_id> -xml-path <path_to_dataset_xml> -workdir <working_directory>
Options:
    -dry-run                Show the command that would be executed without making any changes
    -dataset-folder         The folder name of the dataset (e.g. DATASET_123abcetc)
    -dataset-id             The dataset accession ID to be added to the dataset.xml file
    -user-id                The user ID for the S3 bucket path
    -xml-path               The path to the directory containing the dataset.xml file
    -workdir                The working directory where intermediate files will be stored (default: current directory)
"

S3CMD_INBOX_CONFIG="$HOME/.sda/s3cmd-bp-master-inbox.conf"
INBOX_BUCKET="inbox-2024-01"


# argument parsing
dry_run=false
dataset_id=""
dataset_folder=""
xml_path=""
user_id=""
workdir="."
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -dry-run) dry_run=true ;;
        -dataset-folder) dataset_folder="$2"; shift ;;
        -dataset-id) dataset_id="$2"; shift ;;
        -xml-path) xml_path="$2"; shift ;;
        -user-id) user_id="$2"; shift ;;
        -workdir) workdir="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; echo "$usage"; exit 1 ;;
    esac
    shift
done

if [ -z "$dataset_id" ]; then
    echo "ERROR: -dataset-id is required"
    echo "$usage"
    exit 1
fi

if [ -z "$dataset_folder" ]; then
    echo "ERROR: -dataset-folder is required"
    echo "$usage"
    exit 1
fi

if [ -z "$xml_path" ]; then
    echo "ERROR: -xml-path is required"
    echo "$usage"
    exit 1
fi

dataset_file="$xml_path/dataset.xml"
if [ ! -f "$dataset_file" ]; then
    echo "ERROR: dataset.xml file does not exist in $xml_path"
    exit 1
fi

if [ ! -f "$S3CMD_INBOX_CONFIG" ]; then
    echo "ERROR: S3CMD config file not found at $S3CMD_INBOX_CONFIG"
    exit 1
fi

if [ -z "$user_id" ]; then
    echo "ERROR: user_id variable is not set" 
    exit 1
fi

# sanity check, dataset_folder should be of the format DATASET_123abcetc
if [[ ! "$dataset_folder" =~ ^DATASET_[a-zA-Z0-9]+$ ]]; then
    echo "ERROR: dataset_folder should be of the format DATASET_123abcetc"
    exit 1
fi

if [ ! -d "$workdir" ]; then
    mkdir -p "$workdir"
fi

# test if vault command is available and can access the private key
if ! vault kv get -field=private_key bp-secrets/crypt4gh > /dev/null 2>&1; then
    echo "ERROR: Unable to access private key from vault. Please check your vault configuration and permissions."
    exit 1
fi

if [ "$dry_run" = true ]; then
    echo "Dry run mode enabled. The following command would be executed:"
    echo "modify_dataset \"$dataset_id\" \"$dataset_folder\" \"$dataset_file\""
    exit 0
fi

cp "$dataset_file" "$workdir/dataset.xml"

# prepare for encryption
public_key_file="$workdir/bp_key.pub"
private_key_file="$workdir/c4gh.sec.pem"
curl https://raw.githubusercontent.com/NBISweden/EGA-SE-user-docs/main/crypt4gh_bp_key.pub -o "$public_key_file"
vault kv get -field=private_key bp-secrets/crypt4gh > "$private_key_file"
export C4GH_PASSPHRASE=$(vault kv get -field=password bp-secrets/crypt4gh)

modify_dataset() {
    local dataset_id="$1"
    local dataset_folder="$2"
    local dataset_file="$3"
    # first check if the filed accession already exists in the dataset.xml file
    if grep -q 'accession="' "$dataset_file"; then
        echo "Warning: accession attribute already exists in dataset.xml, check if it is correct and matches the dataset_id provided as argument"
        exit 1
    fi
    # if not, add the accession attribute to the DATASET element
    sed -i.bak -E "s/(<DATASET[^>]* alias=\"[^\"]*\")/\1 accession=\"$dataset_id\"/g" "$dataset_file"

    C4GHGEN=$(crypt4gh generate 2>&1)
    if [[ $C4GHGEN != *"the required flag"* ]]; then
        if ! crypt4gh encrypt --sk "$private_key_file" --recipient_pk "$public_key_file" < "$dataset_file" > "$dataset_file.c4gh"; then
            echo "ERROR: Encryption failed"
            exit 1
        fi
    else
        if ! crypt4gh encrypt -s "$private_key_file" -p "$public_key_file" -f "$dataset_file"; then
            echo "ERROR: Encryption failed"
            exit 1
        fi
    fi

    s3cmd -c $S3CMD_INBOX_CONFIG del s3://"$INBOX_BUCKET"/"$user_id"/"$dataset_folder"/METADATA/dataset.xml.c4gh

    s3cmd -c $S3CMD_INBOX_CONFIG put "$workdir/dataset.xml.c4gh" s3://"$INBOX_BUCKET"/"$user_id"/"$dataset_folder"/METADATA/dataset.xml.c4gh

    # show in green color for done
    echo -e "\e[32mDataset $dataset_id modified and uploaded successfully\e[0m" 
}

modify_dataset "$dataset_id" "$dataset_folder" "$workdir/dataset.xml" 

# clean up intermediate files
rm -f "$workdir/dataset.xml.bak" "$workdir/dataset.xml.c4gh" "$public_key_file" "$private_key_file"