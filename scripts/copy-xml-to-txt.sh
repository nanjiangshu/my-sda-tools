#!/bin/bash

set -ueo pipefail

# Function to echo an error message to stderr and exit
handle_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Wrapper function for executing and checking commands
# It prints the command and then executes it, checking its exit status.
exec_and_check() {
    echo "Executing: $*"
    if ! "$@"; then # "$@" passes all arguments as separate words, safer than eval
        handle_error "Command failed: '$*'"
    fi
}

# Change to the xml-files directory. If it fails, print an error to stderr and exit.
# `cd` is often preferred over `pushd` if you don't need the directory stack.
# If you specifically need pushd/popd for a stack, ensure it's robust.

pushd xml-files >/dev/null || handle_error "Directory 'xml-files' not found or not accessible."

# Execute copy commands and check their success
exec_and_check cp dataset.xml dataset.txt
exec_and_check cp policy.xml policy.txt
exec_and_check cp rems.xml rems.txt

# Return to the previous directory.
# Using 'popd >/dev/null' suppresses its usual output.
popd >/dev/null || handle_error "Failed to return from 'xml-files' directory."

mkdir -p data/xml
cp xml-files/dataset.txt xml-files/rems.txt xml-files/policy.txt data/xml

echo "All files copied successfully."
