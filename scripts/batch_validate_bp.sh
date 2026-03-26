#!/bin/bash
set -euo pipefail

usage="Usage: $0 [-l listfile] [--run] [--check-vault] [dataset_folder_id1 dataset_folder_id2 ...]

Batch validate dataset folders using the validator.sh script. 

Options:
  -l, --list       Path to a file containing dataset IDs (one per line)
  --run            Execute the validation (defaults to dry-run)
  --check-vault    Verify Vault authentication before proceeding
  -h, --help       Display this help message"

dataset_folder_list=()
list_file=""
dry_run=true
verify_vault=true

# Function to check Vault status
check_vault_login() {
    echo "Checking Vault authentication..."
    if ! vault token lookup > /dev/null 2>&1; then
        echo "Error: You are not logged into Vault or your token has expired."
        echo "Please run 'vault login' first."
        exit 1
    fi
    echo "Vault authentication verified."
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "$usage"
            exit 0
            ;;
        -l|--list)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                list_file="$2"
                shift 2
            else
                echo "Error: --list requires a file argument."
                exit 1
            fi
            ;;
        --run)
            dry_run=false
            shift
            ;;
        --check-vault)
            verify_vault=true
            shift
            ;;
        -*)
            echo "Error: Unknown flag $1"
            echo "$usage"
            exit 1
            ;;
        *)
            dataset_folder_list+=("$1")
            shift
            ;;
    esac
done

# Perform Vault check if requested
if [[ "$verify_vault" == true ]]; then
    check_vault_login
fi

validator=/data3/project-sda/BigPicture-Deployment/helpers/dev-tools/validator.sh
if [[ ! -f "$validator" ]]; then
    echo "Error: Validator script not found at $validator"
    exit 1
fi

# Load IDs from list file
if [[ -n "$list_file" ]]; then
    if [[ -f "$list_file" ]]; then
        mapfile -t file_folders < "$list_file"
        dataset_folder_list+=("${file_folders[@]}")
    else
        echo "Error: List file '$list_file' not found."
        exit 1
    fi
fi

if [[ ${#dataset_folder_list[@]} -eq 0 ]]; then
    echo "Error: No dataset folder IDs provided."
    echo "$usage"
    exit 1
fi

for dataset_folder in "${dataset_folder_list[@]}"; do
    [[ -z "$dataset_folder" ]] && continue

    echo "----------------------------------------------------------"
    echo "Processing: $dataset_folder"
    echo "----------------------------------------------------------"

    mkdir -p "$dataset_folder"
    
    (
        cd "$dataset_folder"
        
        user=$(grep "$dataset_folder" /data3/project-sda/misc/bp-submission/inbox-all.s3.txt | head -n 1 | awk '{print $NF}' | awk -F'/' '{print $4}' | tr '_' '@')
        
        if [[ -z "$user" ]]; then
            echo "Warning: Could not find user for $dataset_folder. Skipping..."
            exit 0 
        fi

        bash "$validator" --clean 
        
        cmd=(bash "$validator" -c prod -u "$user" -d "$dataset_folder")
        [[ "$dry_run" == true ]] && cmd+=(--dry-run)
        
        "${cmd[@]}"
    )
done