#!/usr/bin/env python3
"""
Send an email with arbitrary content through the NBIS ticketing system
(FreeScout, https://tickets.nbis.se) using its REST API.

The email is created as a new conversation in a mailbox, with a message thread from an
agent, which FreeScout delivers to the customer by email. The conversation stays in the
mailbox, so there is a record of what was sent.

Settings come from the environment (never from arguments):
  TICKET_API_KEY     FreeScout API key (TICKET_PASSWORD is accepted as an alias)
  TICKET_MAILBOX_ID  id of the mailbox the email is sent from (number in the mailbox URL)
  TICKET_USER_ID     id of the agent the message is sent as (number in /users/profile/<id>)
  TICKET_URL         (optional) default https://tickets.nbis.se

Nothing is sent unless --send is given; the default is a dry run that prints the email.

Usage as a command:
  ./send_email_through_bptickets.py --to a@b.se --subject "Hello" --body-file msg.txt
  echo "Hi there" | ./send_email_through_bptickets.py --to a@b.se --subject "Hello" --send

Usage as a library:
  from send_email_through_bptickets import get_settings, send_email
  send_email(get_settings(), "a@b.se", "Subject", "Body text", status="closed")
"""

import argparse
import html
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_URL = "https://tickets.nbis.se"
STATUSES = ("active", "pending", "closed")


class TicketError(Exception):
    """Raised when the ticketing system rejects or fails a request."""


def get_settings(require_send=True):
    """Read the TICKET_* environment variables. Exit with a message if incomplete."""
    s = {
        "api_key": os.environ.get("TICKET_API_KEY") or os.environ.get("TICKET_PASSWORD", ""),
        "mailbox_id": os.environ.get("TICKET_MAILBOX_ID", ""),
        "user_id": os.environ.get("TICKET_USER_ID", ""),
        "base_url": os.environ.get("TICKET_URL", DEFAULT_URL),
    }
    if require_send and not (s["api_key"] and s["mailbox_id"].isdigit() and s["user_id"].isdigit()):
        sys.exit("Error: set TICKET_API_KEY, TICKET_MAILBOX_ID and TICKET_USER_ID (numbers) "
                 "in the environment to use --send.")
    return s


def text_to_html(body):
    """Escape plain text and keep its line breaks."""
    return html.escape(body).replace("\n", "<br>\n")


def send_email(settings, to_addr, subject, body, status="active", is_html=False):
    """Send one email via the ticketing system. Returns the new conversation id.

    body is plain text unless is_html is True. Raises TicketError on failure.
    """
    mailbox_id = int(settings["mailbox_id"])
    user_id = int(settings["user_id"])
    payload = {
        "type": "email",
        "mailboxId": mailbox_id,
        "status": status,  # active | pending | closed
        "assignTo": user_id,  # keeps it visible under "Mine" for the sender
        "subject": subject,
        "customer": {"email": to_addr},
        "threads": [{"type": "message", "text": body if is_html else text_to_html(body),
                     "user": user_id, "customer": {"email": to_addr}}],
    }
    req = urllib.request.Request(
        f"{settings['base_url'].rstrip('/')}/api/conversations",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json",
                 "X-FreeScout-API-Key": settings["api_key"]},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            # 201 Created, the conversation id is in the X-FreeScout-Conversation-Id header
            return resp.headers.get("X-FreeScout-Conversation-Id")
    except urllib.error.HTTPError as e:
        raise TicketError(f"HTTP {e.code} {e.reason}: {e.read().decode(errors='replace')[:300]!r}") from e
    except urllib.error.URLError as e:
        raise TicketError(str(e)) from e


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--to", required=True, metavar="EMAIL", help="recipient email address")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--body-file", metavar="FILE", help="file with the message (default: read stdin)")
    ap.add_argument("--html", action="store_true", help="body is HTML, not plain text")
    ap.add_argument("--status", default="active", choices=STATUSES,
                    help="status of the created conversation (default: active)")
    ap.add_argument("--send", action="store_true", help="actually send (default: dry run)")
    args = ap.parse_args()

    if args.body_file:
        with open(args.body_file, encoding="utf-8") as fh:
            body = fh.read()
    else:
        body = sys.stdin.read()
    if not body.strip():
        sys.exit("Error: empty message body.")

    if not args.send:
        print(f"--- DRY RUN: to <{args.to}> | {args.subject}\n{body}", file=sys.stderr)
        sys.exit(0)

    try:
        cid = send_email(get_settings(), args.to, args.subject, body,
                         status=args.status, is_html=args.html)
    except TicketError as e:
        sys.exit(f"FAILED for {args.to}: {e}")
    print(f"sent to {args.to}, conversation #{cid}")


if __name__ == "__main__":
    main()
