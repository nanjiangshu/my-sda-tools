#!/usr/bin/env bash
set -euo pipefail

# ========= Default Configuration =========
RUNDIR=$(dirname "$(realpath "$0")")
[[ -d "$RUNDIR" ]] || die "Script directory not found: $RUNDIR"
[[ -f "$RUNDIR/analyze_upload_test.py" ]] || die "Required script not found: $RUNDIR/analyze_upload_test.py"

WORKDIR=""
S3CMDFILE="./s3cmd.conf"
BINPATH=""
SDA_CLI="sda-cli"
OUTDIR="."
SIZES=(2 20 200)    # MB per file
NUMFILE=100         # number of files per dataset
RUN_SIZES=()        # sizes to actually run (default = all)
no_cleanup=false

# ========= Helpers =========
die() { echo "ERROR: $*" >&2; exit 1; }

show_help() {
    cat <<EOF
Usage: $0 [options] <subcommand>

Options:
  -workdir DIR       Required. Working directory where datasets/results/keys are stored
  -config FILE       Path to s3cmd config file (default: ./s3cmd.conf)
  -binpath DIR       Path to directory containing sda-cli (default: found in \$PATH)
  -outdir DIR        Directory to copy results into (default: current folder)
  -size SIZE         Limit operations to one dataset size (can be used multiple times)
  -numfile NUM       Number of files per dataset (default: $NUMFILE)
  -no-cleanup        Do not clean up workdir after run (useful for debugging)
  -h, --help         Show this help message

Subcommands:
  run                Run all steps: create dataset, upload, collect report
  help               Show this help message

Examples:
  $0 -workdir /tmp/sda-test run
EOF
}

# ========= Argument Parsing =========
parse_args() {
    SUBCOMMAND=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -config)    shift; S3CMDFILE="$1" ;;
            -binpath)   shift; BINPATH="$1" ;;
            -workdir)   shift; WORKDIR="$1" ;;
            -outdir)    shift; OUTDIR="$1" ;;
            -size)      shift; RUN_SIZES+=("$1") ;;
            -numfile)   shift; NUMFILE="$1" ;;
            -no-cleanup) no_cleanup=true ;;
            -h|--help)  show_help; exit 0 ;;
            run|help)
                if [[ -n "$SUBCOMMAND" ]]; then
                    die "Multiple subcommands given: $SUBCOMMAND and $1"
                fi
                SUBCOMMAND="$1"
                ;;
            *) die "Unknown argument: $1 (try '$0 help')" ;;
        esac
        shift
    done

    # default if no subcommand
    if [[ -z "$SUBCOMMAND" ]]; then
        show_help
        exit 0
    fi
}

# ========= Environment Setup =========
setup_env() {
    [[ -n "$WORKDIR" ]] || die "You must provide -workdir <dir>"
    mkdir -p "$WORKDIR"
    mkdir -p "$OUTDIR"
    DATA_DIR="$WORKDIR/datasets"
    RESULT_DIR="$WORKDIR/results"
    KEYNAME="c4ghkey"

    [[ -f "$S3CMDFILE" ]] || die "s3cmd config file not found: $S3CMDFILE"

    if [[ -n "$BINPATH" ]]; then
        SDA_CLI="$BINPATH/sda-cli"
    fi
    command -v "$SDA_CLI" >/dev/null 2>&1 || die "sda-cli not found at: $SDA_CLI"

    if [[ ${#RUN_SIZES[@]} -eq 0 ]]; then
        RUN_SIZES=("${SIZES[@]}")
    else
        for s in "${RUN_SIZES[@]}"; do
            [[ " ${SIZES[*]} " == *" $s "* ]] || die "Invalid size: $s. Must be one of: ${SIZES[*]}"
        done
    fi

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "Error: GITHUB_TOKEN is not defined."
        exit 1
    fi

    if ! command -v python > /dev/null 2>&1; then
        echo "Python is not installed. Please install Python and try again."
        exit 1
    fi

    # Check if matplotlib is installed
    if ! python -c "import pkg_resources; pkg_resources.get_distribution('matplotlib')" > /dev/null 2>&1; then
        echo "matplotlib is not installed. Installing ..."
        python -m pip install matplotlib
        if [ $? -ne 0 ]; then
            echo "Failed to install matplotlib. Please check your internet connection or permissions and try again."
            exit 1
        fi
    fi
}

# ========= Core Functions =========
create_dataset() {
    mkdir -p "$DATA_DIR"
    for size in "${RUN_SIZES[@]}"; do
        dir="$DATA_DIR/${size}M"
        mkdir -p "$dir"
        f="$dir/file_${size}M.bin"
        echo "Creating single dataset file: ${size}MB at $f"
        [[ -f "$f" ]] || dd if=/dev/urandom of="$f" bs=1M count=$size status=none
    done
}

upload() {
    mkdir -p "$RESULT_DIR"
    RANDOM_SUFFIX=$((RANDOM % 1000000))
    for size in "${RUN_SIZES[@]}"; do
        dir="$DATA_DIR/${size}M"
        file="$dir/file_${size}M.bin"
        log="$RESULT_DIR/sda_cli_${size}M.txt"
        echo "Uploading dataset ${size}MB ... logging to $log"
        rm -f "$log"
        for i in $(seq 1 $NUMFILE); do
            {
                echo "$i: Uploading $file (iteration $i)"
                time -p "$SDA_CLI" -config "$S3CMDFILE" \
                    upload -encrypt-with-key "$WORKDIR/c4ghkey.pub.pem" \
                    --force-overwrite "$file" \
                    -targetDir "testupload-sda-cli-${size}M-$RANDOM_SUFFIX"
                rm -f "$file.c4gh"
            } >> "$log" 2>&1 || echo "ERROR uploading $file (iteration $i)" >> "$log"
        done
    done
}

collect_report() {
    mkdir -p "$RESULT_DIR"
    for size in "${RUN_SIZES[@]}"; do
        log="$RESULT_DIR/sda_cli_${size}M.txt"
        echo "==== Collect result for dataset ${size}MB ===="
        python "$RUNDIR/analyze_upload_test.py" "$log" || echo "Failed to analyze log $log"
    done
    python "$RUNDIR/plot_upload_status.py" "$RESULT_DIR" || echo "Failed to plot upload status"
    python "$RUNDIR/plot_upload_runtime.py" "$RESULT_DIR" || echo "Failed to plot upload runtime"

    # --- Create info.json ---
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  # ISO 8601 UTC
    uploaded_from=$(curl -s ifconfig.me || echo "unknown")

    cat > "$RESULT_DIR/info.json" <<EOF
{
  "CreatedAt": "$created_at",
  "UploadedFrom": "$uploaded_from"
}
EOF
    copy_results
}

copy_results() {
    echo "Copying results to $OUTDIR ..."
    cp -r "$RESULT_DIR"/* "$OUTDIR"/
}

clean() {
    echo "Cleaning contents of workdir $WORKDIR ..."
    rm -rf "${WORKDIR:?}/"*
}

fetch_pubkey() {
    echo "Fetching public key for uploading ..."
    (cd "$WORKDIR" && wget -q https://raw.githubusercontent.com/NBISweden/EGA-SE-user-docs/main/crypt4gh_bp_key.pub -O c4ghkey.pub.pem ||
        die "Failed to fetch public key. Please check your internet connection or the URL.")
    echo "Public key fetched to $WORKDIR/c4ghkey.pub.pem"
}

run() {
    fetch_pubkey
    create_dataset
    upload
    collect_report
    if [[ "$no_cleanup" == false ]]; then
        echo "=== Cleaning after run ==="
        clean
    else
        echo "Skipping cleanup as -no-cleanup was specified"
    fi
    bash upload_result_to_github.sh "$OUTDIR"
}

# ========= Main =========
parse_args "$@"
setup_env

case "$SUBCOMMAND" in
    run)  run ;;
    help) show_help ;;
esac