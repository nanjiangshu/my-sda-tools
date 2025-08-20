#!/usr/bin/env bash
set -euo pipefail

# ========= Default Configuration =========
WORKDIR=""
S3CMDFILE="./s3cmd.conf"
BINPATH=""
SDA_CLI="sda-cli"
OUTDIR="."
SIZES=(2 20 200)    # MB per file
FILES=100           # number of files per dataset
RUN_SIZES=()        # sizes to actually run (default = all)

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

Subcommands:
  create-dataset      Generate test datasets in workdir
  upload              Upload files using sda-cli
  collect-report      Summarize errors into summary_report.txt
  create-key          Create encryption key pair (c4ghkey.pub.pem / c4ghkey.sec.pem)
  clean               Remove contents of workdir
  runall              Full workflow: create-key, create-dataset, upload, collect-report, then clean
  help                Show this help message

Examples:
  $0 -workdir /tmp/sda-test runall
  $0 -workdir /tmp/sda-test -size 20 upload
  $0 -workdir /tmp/sda-test -size 2 create-dataset
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
        echo "Creating dataset: $FILES files of ${size}MB in $dir"
        for i in $(seq 1 $FILES); do
            f="$dir/file_${i}.bin"
            [[ -f "$f" ]] || dd if=/dev/urandom of="$f" bs=1M count=$size status=none
        done
    done
}

upload() {
    mkdir -p "$OUT_DIR"
    for size in "${RUN_SIZES[@]}"; do
        dir="$DATA_DIR/${size}M"
        log="$OUT_DIR/time_cli_${size}M.txt"
        echo "Uploading dataset ${size}MB ... logging to $log"
        rm -f "$log"
        for file in "$dir"/*; do
            {
                time -p "$SDA_CLI" -config "$S3CMDFILE" \
                    upload -encrypt-with-key "$WORKDIR/c4ghkey.pub.pem" \
                    --force-overwrite "$file" \
                    -targetDir "testupload-sda-cli-${size}M"
            } 2>> "$log" || echo "ERROR uploading $file" >> "$log"
        done
    done
}

collect_report() {
    mkdir -p "$OUT_DIR"
    report="$OUT_DIR/summary_report.txt"
    echo "Generating error summary in $report"
    rm -f "$report"
    for size in "${RUN_SIZES[@]}"; do
        log="$OUT_DIR/time_cli_${size}M.txt"
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
    rm -rf "$WORKDIR"/*
}

create_key() {
    echo "Creating encryption key with sda-cli ..."
    (cd "$WORKDIR" && "$SDA_CLI" createKey c4ghkey)
    echo "Keys created in $WORKDIR:"
    echo "  - c4ghkey.pub.pem (public)"
    echo "  - c4ghkey.sec.pem (private)"
}

runall() {
    echo "=== Runall started ==="
    create_key
    create_dataset
    upload
    collect_report
    echo "=== Cleaning after run ==="
    clean
    echo "=== Runall finished ==="
}

# ========= Main =========
parse_flags "$@"
setup_env

case "$SUBCOMMAND" in
    create-dataset) create_dataset ;;
    upload) upload ;;
    collect-report) collect_report ;;
    clean) clean ;;
    create-key) create_key ;;
    runall) runall ;;
    help|"") show_help ;;
    *) echo "Unknown subcommand: $SUBCOMMAND"; show_help; exit 1 ;;
esac
