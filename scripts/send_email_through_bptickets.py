#!/usr/bin/env python3
"""
Send an email, or reply to an existing conversation, through the NBIS ticketing
system (FreeScout, https://tickets.nbis.se) using its REST API.

New email:  created as a new conversation in a mailbox, with a message thread from an
            agent, which FreeScout delivers to the customer by email. The conversation
            stays in the mailbox, so there is a record of what was sent.
Reply:      with --reply-to ID, the message is added as an agent reply to the existing
            conversation ID (number in its URL) and emailed to its customer.

Settings come from the environment (never from arguments or the YAML file for the key):
  TICKET_API_KEY     FreeScout API key (TICKET_PASSWORD is accepted as an alias)
  TICKET_MAILBOX_ID  id of the mailbox the email is sent from (number in the mailbox URL)
  TICKET_USER_ID     id of the agent the message is sent as (number in /users/profile/<id>)
  TICKET_URL         (optional) default https://tickets.nbis.se
mailbox_id, user_id and url may also be given in the YAML file; the environment wins
only when the YAML file does not set them. The API key is never read from YAML.

Everything else can be given in a YAML file with --config (command-line options
override it). Keys:
  to:          recipient email (new email only)
  subject:     subject (new email only)
  body:        message text (use a block scalar:  body: |)
  body_file:   file with the message, relative to the YAML file (alternative to body)
  html:        true if the body is HTML (default false: plain text)
  status:      active | pending | closed
  reply_to:    conversation id; reply instead of creating a new conversation
  mailbox_id, user_id, url:   optional, see above

Nothing is sent unless --send is given; the default is a dry run that prints the message.

Examples:
  ./send_email_through_bptickets.py --to a@b.se --subject "Hello" --body-file msg.txt --send
  ./send_email_through_bptickets.py --reply-to 1234 --body-file reply.txt --send
  ./send_email_through_bptickets.py --config mail.yaml --send

Example mail.yaml:
  to: a@b.se
  subject: Hello
  status: closed
  body: |
    Dear Jane,

    This is a test message.

    Best regards,
    BP-ops team

Library:
  from send_email_through_bptickets import get_settings, send_email, reply_to_conversation
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
YAML_KEYS = {"to", "subject", "body", "body_file", "html", "status", "reply_to",
             "mailbox_id", "user_id", "url"}


class TicketError(Exception):
    """Raised when the ticketing system rejects or fails a request."""


def get_settings(require_send=True, overrides=None):
    """Read the TICKET_* environment variables; `overrides` (e.g. from YAML) take
    precedence for mailbox_id, user_id and base_url. Exit with a message if incomplete."""
    overrides = overrides or {}
    s = {
        "api_key": os.environ.get("TICKET_API_KEY") or os.environ.get("TICKET_PASSWORD", ""),
        "mailbox_id": str(overrides.get("mailbox_id") or os.environ.get("TICKET_MAILBOX_ID", "")),
        "user_id": str(overrides.get("user_id") or os.environ.get("TICKET_USER_ID", "")),
        "base_url": overrides.get("url") or os.environ.get("TICKET_URL", DEFAULT_URL),
    }
    if require_send and not (s["api_key"] and s["mailbox_id"].isdigit() and s["user_id"].isdigit()):
        sys.exit("Error: TICKET_API_KEY (environment) and the numeric mailbox id and user id "
                 "(TICKET_MAILBOX_ID / TICKET_USER_ID or mailbox_id / user_id in the YAML file) "
                 "are required to use --send.")
    return s


def text_to_html(body):
    """Escape plain text and keep its line breaks."""
    return html.escape(body).replace("\n", "<br>\n")


def _post(settings, path, payload):
    req = urllib.request.Request(
        f"{settings['base_url'].rstrip('/')}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json",
                 "X-FreeScout-API-Key": settings["api_key"]},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.headers
    except urllib.error.HTTPError as e:
        raise TicketError(f"HTTP {e.code} {e.reason}: {e.read().decode(errors='replace')[:300]!r}") from e
    except urllib.error.URLError as e:
        raise TicketError(str(e)) from e


def send_email(settings, to_addr, subject, body, status="active", is_html=False):
    """Send one email as a new conversation. Returns the new conversation id.

    body is plain text unless is_html is True. Raises TicketError on failure.
    """
    user_id = int(settings["user_id"])
    payload = {
        "type": "email",
        "mailboxId": int(settings["mailbox_id"]),
        "status": status,  # active | pending | closed
        "assignTo": user_id,  # keeps it visible under "Mine" for the sender
        "subject": subject,
        "customer": {"email": to_addr},
        "threads": [{"type": "message", "text": body if is_html else text_to_html(body),
                     "user": user_id, "customer": {"email": to_addr}}],
    }
    # 201 Created, the conversation id is in the X-FreeScout-Conversation-Id header
    return _post(settings, "/api/conversations", payload).get("X-FreeScout-Conversation-Id")


def reply_to_conversation(settings, conversation_id, body, status=None, is_html=False):
    """Add an agent reply to an existing conversation; FreeScout emails it to the
    customer. status=None leaves the conversation status unchanged. Raises TicketError."""
    payload = {
        "type": "message",
        "text": body if is_html else text_to_html(body),
        "user": int(settings["user_id"]),
    }
    if status:
        payload["status"] = status
    _post(settings, f"/api/conversations/{int(conversation_id)}/threads", payload)
    return conversation_id


def load_config(path):
    """Load and validate the YAML file. Returns a dict with body_file already resolved."""
    try:
        import yaml
    except ImportError:
        sys.exit("Error: --config needs PyYAML (pip install pyyaml).")
    with open(path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh) or {}
    if not isinstance(cfg, dict):
        sys.exit(f"Error: {path} must contain a YAML mapping of keys.")
    if "api_key" in cfg or "password" in cfg:
        sys.exit("Error: do not put the API key in the YAML file; use TICKET_API_KEY.")
    unknown = set(cfg) - YAML_KEYS
    if unknown:
        sys.exit(f"Error: unknown key(s) in {path}: {', '.join(sorted(unknown))}")
    if cfg.get("body_file"):
        cfg["body_file"] = os.path.join(os.path.dirname(os.path.abspath(path)), cfg["body_file"])
    return cfg


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", metavar="YAML", help="YAML file with the message and its settings")
    ap.add_argument("--to", metavar="EMAIL", help="recipient email address (new email)")
    ap.add_argument("--subject", help="subject (new email)")
    ap.add_argument("--reply-to", metavar="ID", type=int,
                    help="reply to this existing conversation id instead of creating a new one")
    ap.add_argument("--body-file", metavar="FILE", help="file with the message (default: stdin)")
    ap.add_argument("--html", action="store_true", default=None, help="body is HTML, not plain text")
    ap.add_argument("--status", choices=STATUSES,
                    help="conversation status (new email: default active; reply: unchanged)")
    ap.add_argument("--send", action="store_true", help="actually send (default: dry run)")
    args = ap.parse_args()

    cfg = load_config(args.config) if args.config else {}
    # command-line options override the YAML file
    for key in ("to", "subject", "reply_to", "html", "status"):
        v = getattr(args, key)
        if v is not None:
            cfg[key] = v
    if args.body_file:
        cfg["body_file"] = args.body_file
        cfg.pop("body", None)

    if cfg.get("body"):
        body = str(cfg["body"])
    elif cfg.get("body_file"):
        with open(cfg["body_file"], encoding="utf-8") as fh:
            body = fh.read()
    elif args.config:
        sys.exit("Error: no body (set body or body_file in the YAML file, or use --body-file).")
    else:
        body = sys.stdin.read()
    if not body.strip():
        sys.exit("Error: empty message body.")

    reply_to = cfg.get("reply_to")
    status = cfg.get("status")
    if status is not None and status not in STATUSES:
        sys.exit(f"Error: status must be one of {', '.join(STATUSES)}.")
    if not reply_to and not (cfg.get("to") and cfg.get("subject")):
        sys.exit("Error: a new email needs `to` and `subject` (or use --reply-to ID to reply).")
    if reply_to and not str(reply_to).isdigit():
        sys.exit("Error: reply_to must be a conversation id (number).")
    is_html = bool(cfg.get("html"))

    target = (f"REPLY to conversation #{reply_to}" if reply_to
              else f"NEW to <{cfg['to']}> | {cfg['subject']}")
    if not args.send:
        print(f"--- DRY RUN: {target}\n{body}", file=sys.stderr)
        sys.exit(0)

    settings = get_settings(overrides=cfg)
    try:
        if reply_to:
            reply_to_conversation(settings, reply_to, body, status=status, is_html=is_html)
            print(f"replied to conversation #{reply_to}")
        else:
            cid = send_email(settings, cfg["to"], cfg["subject"], body,
                             status=status or "active", is_html=is_html)
            print(f"sent to {cfg['to']}, conversation #{cid}")
    except TicketError as e:
        sys.exit(f"FAILED: {e}")


if __name__ == "__main__":
    main()
