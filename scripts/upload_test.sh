#!/usr/bin/env bash
set -euo pipefail

# ========= Default Configuration =========
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
  -workdir DIR        Required. Working directory where datasets/results/keys are stored
  -config FILE        Path to s3cmd config file (default: ./s3cmd.conf)
  -binpath DIR        Path to directory containing sda-cli (default: found in \$PATH)
  -outdir DIR         Directory to copy results into (default: current folder)
  -size {2|20|200}    Limit operations to one dataset size (default: all sizes)
  -numfile NUM        Number of files per dataset (default: $NUMFILE)
  -no-cleanup         Do not clean up workdir after runall (useful for debugging)

Subcommands:
  runall              Full workflow: create-dataset, upload, collect-report, then clean
  help                Show this help message

  create-dataset      Generate test datasets in workdir
  upload              Upload files using sda-cli
  collect-report      Summarize errors into summary_report.txt
  clean               Remove contents of workdir

Examples:
  $0 -workdir /tmp/sda-test runall
  $0 -workdir /tmp/sda-test -size 2 runall 
EOF
}

# show help if no arguments provided
[[ $# -eq 0 ]] && show_help && exit 0

parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -config) shift; S3CMDFILE="$1" ;;
            -binpath) shift; BINPATH="$1" ;;
            -workdir) shift; WORKDIR="$1" ;;
            -outdir) shift; OUTDIR="$1" ;;
            -size) shift; RUN_SIZES=("$1") ;;   # e.g. -size 2 or 20 or 200
            -numfile) shift; NUMFILE="$1" ;;
            -no-cleanup) no_cleanup=true ;;
            -h|--help) show_help; exit 0 ;;
            help) show_help; exit 0 ;;
            *) break ;;
        esac
        shift
    done
    SUBCOMMAND="${1:-}"
}

setup_env() {
    # Require workdir
    [[ -n "$WORKDIR" ]] || die "You must provide -workdir <dir>"
    mkdir -p "$WORKDIR"
    mkdir -p "$OUTDIR"
    DATA_DIR="$WORKDIR/datasets"
    OUT_DIR="$WORKDIR/results"
    KEYNAME="c4ghkey"

    # s3cmd config
    [[ -f "$S3CMDFILE" ]] || die "s3cmd config file not found: $S3CMDFILE"

    # sda-cli
    if [[ -n "$BINPATH" ]]; then
        SDA_CLI="$BINPATH/sda-cli"
    fi
    command -v "$SDA_CLI" >/dev/null 2>&1 || die "sda-cli not found at: $SDA_CLI"

    # Sizes to run
    if [[ ${#RUN_SIZES[@]} -eq 0 ]]; then
        RUN_SIZES=("${SIZES[@]}")
    else
        for s in "${RUN_SIZES[@]}"; do
            [[ " ${SIZES[*]} " == *" $s "* ]] || die "Invalid size: $s. Must be one of: ${SIZES[*]}"
        done
    fi
}

create_dataset() {
    mkdir -p "$DATA_DIR"
    for size in "${RUN_SIZES[@]}"; do
        dir="$DATA_DIR/${size}M"
        mkdir -p "$dir"
        echo "Creating dataset: $NUMFILE files of ${size}MB in $dir"
        for i in $(seq 1 $NUMFILE); do
            f="$dir/file_${i}.bin"
            [[ -f "$f" ]] || dd if=/dev/urandom of="$f" bs=1M count=$size status=none
        done
    done
}

upload() {
    mkdir -p "$OUT_DIR"
    for size in "${RUN_SIZES[@]}"; do
        dir="$DATA_DIR/${size}M"
        log="$OUT_DIR/sda_cli_${size}M.txt"
        echo "Uploading dataset ${size}MB ... logging to $log"
        rm -f "$log"
        for i in $(seq 1 $NUMFILE); do
            file="$dir/file_${i}.bin"
            {
                echo "$i: Uploading $file"
                time -p "$SDA_CLI" -config "$S3CMDFILE" \
                    upload -encrypt-with-key "$WORKDIR/c4ghkey.pub.pem" \
                    --force-overwrite "$file" \
                    -targetDir "testupload-sda-cli-${size}M"
            } >> "$log" 2>&1 || echo "ERROR uploading $file" >> "$log"
        done
    done
}

collect_report() {
    mkdir -p "$OUT_DIR"
    report="$OUT_DIR/summary_report.txt"
    echo "Generating error summary in $report"
    rm -f "$report"
    for size in "${RUN_SIZES[@]}"; do
        log="$OUT_DIR/sda_cli_${size}M.txt"
        echo "==== Dataset ${size}MB ====" >> "$report"
        if [[ -f "$log" ]]; then
            grep "ERROR" "$log" >> "$report" || true
            echo "Total errors: $(grep -c "ERROR" "$log" || true)" >> "$report"
            echo "" >> "$report"
        else
            echo "No log found for ${size}MB dataset" >> "$report"
        fi
    done
    echo "Summary written to $report"
    copy_results
}

copy_results() {
    echo "Copying results to $OUTDIR ..."
    cp -r "$OUT_DIR"/* "$OUTDIR"/
}

clean() {
    echo "Cleaning contents of workdir $WORKDIR ..."
    rm -rf "${WORKDIR:?}/"*

}

fetch_pubkey() {
    echo "Fetching public key with sda-cli ..."
    (cd "$WORKDIR" && wget -q https://raw.githubusercontent.com/NBISweden/EGA-SE-user-docs/main/crypt4gh_bp_key.pub -O c4ghkey.pub.pem ||
        die "Failed to fetch public key. Please check your internet connection or the URL.")
    echo "Public key fetched to $WORKDIR/c4ghkey.pub.pem"
}

runall() {
    echo "=== Runall started ==="
    fetch_pubkey
    create_dataset
    upload
    collect_report
    if [[ "$no_cleanup" == false ]]; then
        echo "=== Cleaning after runall ==="
        clean
    else
        echo "Skipping cleanup as -no-cleanup was specified"
    fi
    echo "=== Runall completed ==="
}

# ========= Main =========
parse_flags "$@"
setup_env

case "$SUBCOMMAND" in
    create-dataset) create_dataset ;;
    upload) upload ;;
    collect-report) collect_report ;;
    clean) clean ;;
    runall) runall ;;
    help|"") show_help ;;
    *) echo "Unknown subcommand: $SUBCOMMAND"; show_help; exit 1 ;;
esac
