#!/usr/bin/env python3

import argparse
import sys

# syncedfile.txt is the output of "s3cmd ls -r s3://bigpicture-202603/$DATASET_FOLDER" and contains the list of files that have been synced to the S3 bucket.
# stableid_filepath.txt is the output of "get_file_stableids_from_datasetid.sh" and contains the list of stable IDs and their corresponding file paths.

def main():
    parser = argparse.ArgumentParser(description="Find StableIDs whose files are missing in the sync list.")
    parser.add_argument("--synced", required=True, help="Path to syncedfile.txt")
    parser.add_argument("--stableid", required=True, help="Path to stableid_filepath.txt")
    
    args = parser.parse_args()

    synced_paths = set()
    try:
        with open(args.synced, 'r') as f:
            for line in f:
                if 's3://' in line:
                    parts = line.split('/')
                    if len(parts) > 3:
                        path = "/".join(parts[3:]).strip()
                        synced_paths.add(path)
    except FileNotFoundError:
        print(f"Error: Did not find file {args.synced}")
        sys.exit(1)

    try:
        with open(args.stableid, 'r') as f:
            found_missing = False
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    stable_id = parts[0]
                    file_path = parts[1]
                    
                    if file_path not in synced_paths:
                        print(stable_id)
                        found_missing = True
            
            if not found_missing:
                print("# All files in the stableid list are present in the sync file.")
                
    except FileNotFoundError:
        print(f"Error: Did not find file {args.stableid}")
        sys.exit(1)

if __name__ == "__main__":
    main()