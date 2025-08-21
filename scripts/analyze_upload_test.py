#!/usr/bin/env python3
import os
import re
import sys


def parse_upload_log(filepath):
    runtimes = []
    statuses = []

    with open(filepath, "r") as f:
        block = []
        for line in f:
            line = line.rstrip("\n")

            # new upload block starts
            if re.match(r"^\d+:\s+Uploading", line):
                if block:
                    process_block(block, runtimes, statuses)
                block = [line]
            else:
                block.append(line)

        # process last block
        if block:
            process_block(block, runtimes, statuses)

    return runtimes, statuses


def process_block(block, runtimes, statuses):
    block_text = "\n".join(block)

    # Extract runtime
    match = re.search(r"real\s+([\d.]+)", block_text)
    if match:
        runtimes.append(match.group(1))  # keep as string

    # Classify outcome
    if "ERROR uploading" not in block_text:
        statuses.append("SUCCESS")
    elif "status code: 503" in block_text:
        statuses.append("503-error")
    elif "status code: 413" in block_text:
        statuses.append("413-error")
    elif "status code: 500" in block_text:
        statuses.append("500-error")
    else:
        statuses.append("OTHER-ERROR")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <upload_log_file>")
        sys.exit(1)

    input_file = sys.argv[1]
    if not os.path.isfile(input_file):
        print(f"Error: File not found: {input_file}")
        sys.exit(1)

    runtimes, statuses = parse_upload_log(input_file)

    base = os.path.splitext(input_file)[0]
    runtime_file = base + ".runtime.txt"
    status_file = base + ".upload_status.txt"

    with open(runtime_file, "w") as f:
        for r in runtimes:
            f.write(r + "\n")

    with open(status_file, "w") as f:
        for s in statuses:
            f.write(s + "\n")

    print(f"Written: {runtime_file}")
    print(f"Written: {status_file}")


if __name__ == "__main__":
    main()
