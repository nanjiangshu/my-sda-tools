#!/usr/bin/env bash
set -euo pipefail

S3_CONFIG="$HOME/.sda/s3cmd-bp-master-inbox.conf"
NO_OVERWRITE=false

# -----------------------------------------------------------------------------
# Parse command-line options
# -----------------------------------------------------------------------------
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-overwrite|-n)
      NO_OVERWRITE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--no-overwrite|-n] [input_file1 input_file2 ...]"
      exit 0
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

# -----------------------------------------------------------------------------
# 1. Obtain input files (s3cmd ls -r) if not supplied or if overwrite allowed
# -----------------------------------------------------------------------------
FILE1="inbox-2024-01.all.txt"
FILE2="inbox.all.txt"

if [[ $# -gt 0 ]]; then
    INPUT_FILES=("$@")
else
    INPUT_FILES=("$FILE1" "$FILE2")

    if [[ "$NO_OVERWRITE" == false ]] || [[ ! -f "$FILE1" ]]; then
        echo "Fetching s3://inbox-2024-01/ listing..." >&2
        s3cmd -c "$S3_CONFIG" ls -r s3://inbox-2024-01/ > "$FILE1" &
        PID1=$!
    else
        echo "Reusing existing $FILE1" >&2
        PID1=""
    fi

    if [[ "$NO_OVERWRITE" == false ]] || [[ ! -f "$FILE2" ]]; then
        echo "Fetching s3://inbox/ listing..." >&2
        s3cmd -c "$S3_CONFIG" ls -r s3://inbox/ > "$FILE2" &
        PID2=$!
    else
        echo "Reusing existing $FILE2" >&2
        PID2=""
    fi

    [[ -n "$PID1" ]] && wait "$PID1"
    [[ -n "$PID2" ]] && wait "$PID2"
fi

# -----------------------------------------------------------------------------
# Function to parse human-readable sizes (K, M, G, T, B) into raw bytes
# -----------------------------------------------------------------------------
parse_bytes_awk='
    function parse_size(sz,   val, unit) {
        if (sz ~ /^[0-9]+$/) return sz + 0;
        val = substr(sz, 1, length(sz)-1) + 0;
        unit = toupper(substr(sz, length(sz)));
        if (unit == "K") return val * 1024;
        if (unit == "M") return val * 1024 * 1024;
        if (unit == "G") return val * 1024 * 1024 * 1024;
        if (unit == "T") return val * 1024 * 1024 * 1024 * 1024;
        if (unit == "P") return val * 1024 * 1024 * 1024 * 1024 * 1024;
        return val;
    }
    function hr(b,   units, u, size) {
        split("B K M G T P", units, " ")
        u = 1
        size = b
        while (size >= 1024 && u < 6) {
            size /= 1024
            u++
        }
        if (u == 1) return sprintf("%dB", size)
        else if (size == int(size)) return sprintf("%d%s", size, units[u])
        else return sprintf("%.1f%s", size, units[u])
    }
'

# -----------------------------------------------------------------------------
# Core processing function for a single file
# -----------------------------------------------------------------------------
process_file() {
    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        echo "Error: Input file '$input_file' not found." >&2
        return 1
    fi

    local bucket_name="inbox"
    if [[ "$input_file" == *"inbox-2024-01"* ]]; then
        bucket_name="inbox-2024-01"
    fi

    echo "Processing $input_file locally..." >&2

    echo "================================================================================"
    echo " RESULTS FOR: $input_file (s3://${bucket_name}/)"
    echo "================================================================================"

    awk "
        $parse_bytes_awk

        {
            date = \$1
            size_str = \$3

            idx = index(\$0, \"s3://\")
            if (idx > 0) {
                path = substr(\$0, idx)
                n = split(path, parts, \"/\")
                for (i = 1; i <= n; i++) {
                    if (parts[i] ~ /^DATASET_/) {
                        user_dir = parts[i-1]
                        dataset_dir = parts[i]
                        dir = user_dir \"/\" dataset_dir

                        # Accumulate size
                        bytes = parse_size(size_str)
                        total_bytes[dir] += bytes

                        # Track dates
                        if (!(dir in min_date) || date < min_date[dir]) {
                            min_date[dir] = date
                        }
                        if (!(dir in max_date) || date > max_date[dir]) {
                            max_date[dir] = date
                        }
                        break
                    }
                }
            }
        }
        END {
            for (dir in total_bytes) {
                bytes = total_bytes[dir]
                human_size = hr(bytes)
                d1 = min_date[dir]
                d2 = max_date[dir]
                printf \"%020d\t%s %s %s %s\n\", bytes, human_size, d1, d2, dir
            }
        }
    " "$input_file" | sort -r | cut -f2-

    echo ""
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------
for file in "${INPUT_FILES[@]}"; do
    process_file "$file"
done