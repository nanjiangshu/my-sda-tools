#!/bin/bash

# This script reads a mapping file that contains file IDs and their corresponding full paths.
# It then moves files from a source directory to their new locations based on the mapping.

# Configuration
MAPPING_FILE="fileid_filepath_list.txt"
SOURCE_DIR="metadata"
OUTDIR=""

# argument parsing for mapping file and source directory
usage="
Usage: $0 [-m mapping_file] [-s source_directory] [-o output_directory]
Options:
  -m mapping_file      Path to the mapping file (default: fileid_filepath_list.txt)
  -s source_directory  Directory where the source files are located (default: metadata)
  -o output_directory  Directory where the files will be moved (default: current directory)
"
while getopts "m:s:o:h" opt; do
  case $opt in
    m) MAPPING_FILE="$OPTARG" ;;
    s) SOURCE_DIR="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    h) echo "$usage"; exit 0 ;;
    *) echo "$usage"; exit 1 ;;
  esac
done

# Check if mapping file exists
if [[ ! -f "$MAPPING_FILE" ]]; then
    echo "Error: Mapping file $MAPPING_FILE not found."
    exit 1
fi

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory $SOURCE_DIR not found."
    exit 1
fi

echo "Starting file reorganization..."

# Read the mapping file line by line
while IFS='|' read -r file_id full_path || [[ -n "$file_id" ]]; do
    
    # 1. Define the source file path
    src_file="$SOURCE_DIR/$file_id"
    
    # 2. Prepare the destination path
    # Remove the .c4gh extension from the mapping path
    dest_path="${full_path%.c4gh}"
    
    # 3. Process the file
    if [[ -f "$src_file" ]]; then
        # Create the directory structure (e.g., DATASET_XXXX/METADATA/)
        dest_dir=$(dirname "$dest_path")
        if [[ -n "$OUTDIR" ]]; then
            dest_dir="$OUTDIR/$dest_dir"
        fi
        mkdir -p "$dest_dir"
        
        # Move the file to the new location
        mv "$src_file" "$dest_dir/$(basename "$dest_path")"
        echo "Moved: $file_id -> $dest_dir/$(basename "$dest_path")"
    else
        echo "Warning: Source file $src_file not found. Skipping..."
    fi

done < "$MAPPING_FILE"

echo "Reorganization complete."
