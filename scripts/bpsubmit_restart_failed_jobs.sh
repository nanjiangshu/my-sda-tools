#!/usr/bin/env bash

set -uo pipefail

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [-n NAMESPACE] [-r BASE_DIR] [-y] FAILED_JOBS_FILE"
    echo "  FAILED_JOBS_FILE  Output of 'kubectl get jobs' listing, e.g. failed_jobs_2026-11-10.txt"
    echo "                    (first column = job id, e.g. dataset-0a59c13; only lines with"
    echo "                    status 'Failed' are processed)"
    echo "  -n  Kubernetes namespace (default: sda-prod)"
    echo "  -r  Base directory holding the dataset folders (default: current directory)"
    echo "  -y  Do not ask for confirmation"
    echo ""
    echo "For every job id (dataset-0a59c13) the script:"
    echo "  1. cd into DATASET_0A59C13 and sources DATASET_0A59C13.info.conf"
    echo "  2. deletes the job if it exists and is Failed"
    echo "  3. sets CLIENT_ACCESS_TOKEN in DATASET_0A59C13.yaml to \$ACCESS_TOKEN (taken from the environment)"
    echo "  4. kubectl apply --server-side -f DATASET_0A59C13.yaml"
    exit 1
}

NAMESPACE="sda-prod"
BASE_DIR="$(pwd)"
ASSUME_YES=0

while getopts ":n:r:yh" opt; do
    case "${opt}" in
        n) NAMESPACE="${OPTARG}" ;;
        r) BASE_DIR="${OPTARG}" ;;
        y) ASSUME_YES=1 ;;
        h|*) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 1 ]] || usage
[[ -n "${ACCESS_TOKEN:-}" ]] || { echo "[!] ACCESS_TOKEN is not set in the environment" >&2; exit 1; }
INPUT_FILE="$1"
[[ -f "$INPUT_FILE" ]] || { echo "[!] Input file not found: $INPUT_FILE" >&2; exit 1; }
INPUT_FILE="$(cd "$(dirname "$INPUT_FILE")" && pwd)/$(basename "$INPUT_FILE")"
BASE_DIR="$(cd "$BASE_DIR" && pwd)" || exit 1

# Collect job ids (first column) of lines whose status column is Failed
mapfile -t JOBS < <(awk '$2 == "Failed" {print $1}' "$INPUT_FILE")
if [[ ${#JOBS[@]} -eq 0 ]]; then
    echo "[!] No Failed jobs found in $INPUT_FILE" >&2
    exit 1
fi

echo "[*] Namespace: $NAMESPACE"
echo "[*] Base dir:  $BASE_DIR"
echo "[*] ${#JOBS[@]} failed job(s) to restart:"
printf '      %s\n' "${JOBS[@]}"
if [[ $ASSUME_YES -ne 1 ]]; then
    read -r -p "Proceed? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# Replace the value of CLIENT_ACCESS_TOKEN in a yaml file (the 'value:' line after
# '- name: CLIENT_ACCESS_TOKEN'), keeping indentation. Token is passed via the
# environment so special characters are not interpreted.
set_token() {
    local yaml="$1" tmp
    tmp="$(mktemp "${yaml}.XXXXXX")" || return 1
    NEWTOKEN="$ACCESS_TOKEN" awk '
        found && /^[[:space:]]*value:/ {
            match($0, /^[[:space:]]*/)
            print substr($0, 1, RLENGTH) "value: \"" ENVIRON["NEWTOKEN"] "\""
            found = 0; done = 1; next
        }
        /name:[[:space:]]*CLIENT_ACCESS_TOKEN[[:space:]]*$/ { found = 1 }
        { print }
        END { exit(done ? 0 : 1) }
    ' "$yaml" > "$tmp" || { rm -f "$tmp"; return 1; }
    cat "$tmp" > "$yaml" && rm -f "$tmp"
}

OK=()
FAIL=()

process_job() {
    local jobid="$1" folder dir
    folder="$(echo "$jobid" | tr '[:lower:]-' '[:upper:]_')"
    dir="$BASE_DIR/$folder"

    [[ -d "$dir" ]] || { echo "[!] Directory not found: $dir"; return 1; }
    cd "$dir" || return 1

    local info="${folder}.info.conf" yaml="${folder}.yaml"
    [[ -f "$info" ]] || { echo "[!] Missing $dir/$info"; return 1; }
    [[ -f "$yaml" ]] || { echo "[!] Missing $dir/$yaml"; return 1; }

    # shellcheck disable=SC1090
    source "$info"

    # Delete the job only if it exists and has failed
    local failed
    failed="$(kubectl -n "$NAMESPACE" get job "$jobid" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)"
    if [[ "$failed" == "True" ]]; then
        echo "[+] Deleting failed job $jobid"
        kubectl -n "$NAMESPACE" delete job "$jobid" || return 1
    elif kubectl -n "$NAMESPACE" get job "$jobid" >/dev/null 2>&1; then
        echo "[!] Job $jobid exists but is not Failed; skipping"
        return 1
    else
        echo "[*] Job $jobid does not exist; nothing to delete"
    fi

    set_token "$yaml" || { echo "[!] CLIENT_ACCESS_TOKEN entry not found/updated in $yaml"; return 1; }
    echo "[+] Updated CLIENT_ACCESS_TOKEN in $yaml"

    kubectl -n "$NAMESPACE" apply --server-side -f "$yaml" || return 1
}

for jobid in "${JOBS[@]}"; do
    echo "=== $jobid ==="
    # Run in a subshell so sourced variables and cd do not leak between datasets
    if ( process_job "$jobid" ); then
        OK+=("$jobid")
    else
        FAIL+=("$jobid")
    fi
done

echo
echo "[*] Restarted: ${#OK[@]}, failed: ${#FAIL[@]}"
if [[ ${#FAIL[@]} -gt 0 ]]; then
    printf '    FAILED: %s\n' "${FAIL[@]}"
    exit 1
fi
