#!/usr/bin/env python3
"""
Send "no ticket" cleanup emails to the uploaders of datasets in the S3 inbox.

Input files are the *_with_owner_no_ticket.txt files, with rows like:
  SIZE MIN_DATE MAX_DATE <userid>_lifescience-ri.eu/DATASET_xxx  "no_ticket"  owner="Name"  email="a@b.se"

This script only builds the email content. Sending is done by the generic
send_email_through_bptickets.py (same directory), which reads its settings
(TICKET_API_KEY, TICKET_MAILBOX_ID, TICKET_USER_ID, TICKET_URL) from the environment.
Datasets of the same uploader are combined into one email.

Nothing is sent unless --send is given; the default is a dry run that prints the emails.

Example:
  ./send_cleanup_emails.py output_inbox_older_than_60_with_owner_no_ticket.txt \
      output_inbox-2024-01_with_owner_no_ticket.txt
  TICKET_API_KEY=... TICKET_MAILBOX_ID=1 TICKET_USER_ID=2 ./send_cleanup_emails.py --send <files>
"""

import argparse
import re
import sys
from collections import OrderedDict

from send_email_through_bptickets import TicketError, get_settings, send_email

SUBJECT = "Cleanup of S3 inbox: do you still need your uploaded dataset(s)?"

BODY = """Dear {name},

We are currently cleaning up our S3 inbox storage and found {what} that you uploaded some time ago and {have} no ticket in our ticketing system:

{items}

Could you please check whether {this} still {need} to be ingested? If so, just let us know by replying to this email and we will take care of it.

If we don't hear from you within one week, we will go ahead and delete {it}.

Thank you for your help!

Best regards,
BP-ops team
"""

ROW_RE = re.compile(r'^(\S+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{4}-\d{2}-\d{2})\s+(\S+)')
OWNER_RE = re.compile(r'owner="([^"]*)"')
EMAIL_RE = re.compile(r'email="([^"]*)"')


def parse_files(paths):
    """Return (OrderedDict email -> {name, datasets[]}, skipped rows)."""
    users = OrderedDict()
    skipped = []
    seen = set()
    for path in paths:
        with open(path) as fh:
            for line in fh:
                m = ROW_RE.match(line)
                if not m:
                    continue  # header / comment lines
                size, _, max_date, directory = m.groups()
                owner = OWNER_RE.search(line)
                email = EMAIL_RE.search(line)
                if not owner or not email or "@" not in email.group(1):
                    skipped.append(directory)
                    continue
                folder = directory.rsplit("/", 1)[-1]
                key = (email.group(1), folder)
                if key in seen:
                    continue
                seen.add(key)
                u = users.setdefault(email.group(1), {"name": owner.group(1), "datasets": []})
                u["datasets"].append({"folder": folder, "size": size, "date": max_date})
    return users, skipped


def clean_name(name):
    """Drop trailing number tokens, e.g. "Johann Mueller 2023" -> "Johann Mueller"."""
    return re.sub(r"(\s+\d+)+\s*$", "", name).strip() or name


def build_email(name, datasets):
    n = len(datasets)
    items = "\n".join(
        f"  - {d['folder']}  (size {d['size']}, last modified {d['date']})" for d in datasets
    )
    return BODY.format(
        name=clean_name(name),
        what="the dataset below" if n == 1 else f"{n} datasets",
        items=items,
        this="this dataset" if n == 1 else "these datasets",
        it="it" if n == 1 else "them",
        have="has" if n == 1 else "have",
        need="needs" if n == 1 else "need",
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="*_with_owner_no_ticket.txt input files")
    ap.add_argument("--send", action="store_true", help="actually send (default: dry run)")
    ap.add_argument("--only", metavar="EMAIL", help="restrict to this one uploader email")
    ap.add_argument("--status", default="active", choices=["active", "pending", "closed"],
                    help="status of the created conversation (default: active, so replies show up)")
    args = ap.parse_args()

    users, skipped = parse_files(args.files)
    if args.only:
        users = OrderedDict((e, u) for e, u in users.items() if e == args.only)
    for d in skipped:
        print(f"WARNING: no owner/email for {d}, skipped", file=sys.stderr)

    settings = get_settings() if args.send else None

    failures = 0
    for email, u in users.items():
        body = build_email(u["name"], u["datasets"])
        if not args.send:
            print(f"--- DRY RUN: to {u['name']} <{email}> | {SUBJECT}\n{body}")
            continue
        try:
            cid = send_email(settings, email, SUBJECT, body, status=args.status)
            print(f"sent to {email} ({len(u['datasets'])} dataset(s)), conversation #{cid}")
        except TicketError as e:
            failures += 1
            print(f"FAILED for {email}: {e}", file=sys.stderr)

    print(f"\n{len(users)} uploader(s), {sum(len(u['datasets']) for u in users.values())} dataset(s)"
          f"{'' if args.send else ' (dry run, nothing sent)'}", file=sys.stderr)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
