#!/usr/bin/env python3
"""
Filter an `s3cmd ls -r` listing and print the S3 URIs of objects older than
a given number of days, optionally restricted to URIs containing a keyword.

Input lines look like:
    2026-01-08 18:47      12345  s3://inbox/user_lifescience-ri.eu/DATASET/file.c4gh
"""
import argparse
import os
import sys
from datetime import datetime, timedelta, timezone


def non_negative_int(value):
    ivalue = int(value)
    if ivalue < 0:
        raise argparse.ArgumentTypeError(f"must be >= 0, got {value}")
    return ivalue


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Filter S3 file lists based on upload age and keyword matching."
    )
    parser.add_argument(
        "-d", "--days",
        type=non_negative_int,
        default=30,
        help="Age threshold in days, print objects older than this (default: 30)"
    )
    parser.add_argument(
        "-k", "--keyword",
        type=str,
        default="",
        help="Substring to match in the S3 URI (case-insensitive)"
    )
    parser.add_argument(
        "file",
        nargs="?",
        default="-",
        help="Input text file containing the S3 listing (default: stdin)"
    )
    return parser.parse_args()


def filter_files(input_stream, output_stream, days, keyword):
    """Write S3 URIs older than `days` that contain `keyword` to `output_stream`.

    Returns the number of non-empty lines that could not be parsed.
    """
    threshold_date = datetime.now(timezone.utc) - timedelta(days=days)
    keyword_lower = keyword.lower()
    num_skipped = 0

    for line in input_stream:
        line = line.rstrip("\r\n")
        if not line.strip():
            continue

        # Split into date, time, size and URI only, so that keys containing
        # spaces are kept intact. "DIR" lines have fewer fields and are skipped.
        parts = line.split(maxsplit=3)
        if len(parts) < 4 or not parts[3].startswith("s3://"):
            num_skipped += 1
            continue
        date_str = f"{parts[0]} {parts[1]}"
        s3_uri = parts[3]

        try:
            # s3cmd prints the S3 LastModified timestamp, which is in UTC
            file_date = datetime.strptime(date_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
        except ValueError:
            num_skipped += 1
            continue

        if keyword_lower and keyword_lower not in s3_uri.lower():
            continue

        if file_date < threshold_date:
            output_stream.write(s3_uri + "\n")

    return num_skipped


def main():
    args = parse_arguments()

    # surrogateescape passes any non UTF-8 bytes in object keys through unchanged
    output_stream = open(sys.stdout.fileno(), "w", encoding="utf-8",
                         errors="surrogateescape", closefd=False)
    if args.file == "-":
        input_stream = open(sys.stdin.fileno(), encoding="utf-8",
                            errors="surrogateescape", closefd=False)
    else:
        try:
            input_stream = open(args.file, encoding="utf-8", errors="surrogateescape")
        except OSError as e:
            sys.exit(f"Error: cannot open {args.file}: {e.strerror}")

    with input_stream, output_stream:
        num_skipped = filter_files(input_stream, output_stream, args.days, args.keyword)

    if num_skipped:
        print(f"Warning: skipped {num_skipped} line(s) that are not object entries "
              "(e.g. DIR lines or malformed lines)", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # Output piped into e.g. `head` that exited early
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        sys.exit(1)
