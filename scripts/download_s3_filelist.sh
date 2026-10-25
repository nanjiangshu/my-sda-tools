#!/usr/bin/env bash

# This script downloads a list of S3 URIs (one per line) with s3cmd into
# OUTPUT_DIR, keeping the folder structure of the objects. The list is read
# from a file or from stdin, e.g.
#   grep organisation.xml bpstaging-inbox-all.s3.txt | filter_s3_by_date.py -d 30 \
#       | download_s3_filelist.sh -outdir outdir
set -uo pipefail

# ------------------------------------------------------------------------------
# Usage / Help
# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -o OUTPUT_DIR [-b] [-c S3CMD_CONF] [-h] [LIST_FILE]"
    echo "  -o, -outdir, --outdir  Output folder (Mandatory)"
    echo "  -b, --keep-bucket      Keep the bucket name as top folder, i.e."
    echo "                         OUTPUT_DIR/<bucket>/<user>/... instead of OUTPUT_DIR/<user>/..."
    echo "  -c, --config           s3cmd config file (default: ~/.sda/s3cmd-bp-master-inbox.conf)"
    echo "  -h, --help             Show this help message"
    echo "  LIST_FILE              File with one S3 URI per line (default: stdin)"
    echo ""
    echo "Already downloaded files are skipped, so the script can be rerun safely."
    exit 1
}

OUTPUT_DIR=""
KEEP_BUCKET=false
S3CMD_CONF="$HOME/.sda/s3cmd-bp-master-inbox.conf"
LIST_FILE=""

# Parse options by hand so that both -o and -outdir / --outdir are accepted
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|-outdir|--outdir)
            [[ $# -ge 2 ]] || { echo "[-] Error: Option $1 requires an argument." >&2; usage; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -b|--keep-bucket)
            KEEP_BUCKET=true
            shift
            ;;
        -c|--config)
            [[ $# -ge 2 ]] || { echo "[-] Error: Option $1 requires an argument." >&2; usage; }
            S3CMD_CONF="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -)
            LIST_FILE=""
            shift
            ;;
        -*)
            echo "[-] Error: Invalid option $1." >&2
            usage
            ;;
        *)
            if [[ -n "$LIST_FILE" ]]; then
                echo "[-] Error: Only one LIST_FILE can be given." >&2
                usage
            fi
            LIST_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "[-] Error: -o OUTPUT_DIR is mandatory." >&2
    usage
fi

if ! command -v s3cmd &>/dev/null; then
    echo "[-] Error: s3cmd is not in PATH." >&2
    exit 1
fi
if [[ ! -f "$S3CMD_CONF" ]]; then
    echo "[-] Error: $S3CMD_CONF not found!" >&2
    exit 1
fi

if [[ -n "$LIST_FILE" ]]; then
    if [[ ! -f "$LIST_FILE" ]]; then
        echo "[-] Error: List file '$LIST_FILE' not found." >&2
        exit 1
    fi
    exec 3< "$LIST_FILE"
else
    if [[ -t 0 ]]; then
        echo "[-] Error: No LIST_FILE given and nothing piped to stdin." >&2
        usage
    fi
    exec 3<&0
fi

mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# Download Each URI
# ------------------------------------------------------------------------------
NUM_OK=0
NUM_SKIPPED=0
FAILED=()

# Read from fd 3 so that s3cmd cannot consume the list
while IFS= read -r uri <&3 || [[ -n "$uri" ]]; do
    uri="${uri%$'\r'}"
    if [[ -z "${uri//[[:space:]]/}" ]]; then
        continue
    fi
    if [[ "$uri" != s3://*/* ]]; then
        echo "[!] Warning: Not an S3 object URI, skipping: $uri" >&2
        FAILED+=("$uri (not an S3 object URI)")
        continue
    fi

    if [[ "$KEEP_BUCKET" == true ]]; then
        rel="${uri#s3://}"
    else
        rel="${uri#s3://*/}"
    fi
    dest="${OUTPUT_DIR%/}/${rel}"

    if [[ -f "$dest" ]]; then
        echo "[=] Exists, skipping: $dest"
        NUM_SKIPPED=$((NUM_SKIPPED + 1))
        continue
    fi

    mkdir -p "$(dirname "$dest")"
    echo "[+] Downloading $uri"
    # Download to a .part file first, so an interrupted download is not
    # mistaken for a complete file on the next run
    if s3cmd -c "$S3CMD_CONF" get --force --no-progress "$uri" "${dest}.part" </dev/null >/dev/null \
        && mv "${dest}.part" "$dest"; then
        NUM_OK=$((NUM_OK + 1))
    else
        echo "[-] Failed: $uri" >&2
        rm -f "${dest}.part"
        FAILED+=("$uri")
    fi
done
exec 3<&-

# ------------------------------------------------------------------------------
# Summary Report
# ------------------------------------------------------------------------------
echo "=========================================================================="
echo " Download summary (output folder: ${OUTPUT_DIR})"
echo "   Downloaded             : ${NUM_OK}"
echo "   Skipped (already exist): ${NUM_SKIPPED}"
echo "   Failed                 : ${#FAILED[@]}"
for f in ${FAILED[@]+"${FAILED[@]}"}; do
    echo "     - $f"
done
echo "=========================================================================="

if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
fi
