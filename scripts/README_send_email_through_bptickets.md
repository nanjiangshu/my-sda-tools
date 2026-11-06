# send_email_through_bptickets.py

Send an email, or reply to an existing conversation, through the NBIS ticketing
system (FreeScout, https://tickets.nbis.se). Every email is created as a
conversation in a mailbox, so a record of what was sent stays in the ticketing
system.

The script is generic: it takes any recipient, subject and body. Scripts that
generate email content (for example `send_cleanup_emails.py`) call it.

## Setup

Set the credentials in the environment. The API key is never read from
arguments or from a YAML file.

```bash
export TICKET_API_KEY=your_api_key     # FreeScout: Manage -> API & Webhooks
export TICKET_MAILBOX_ID=2             # number after /mailbox/ in the mailbox URL
export TICKET_USER_ID=9                # number in /users/profile/<id> (your agent id)
export TICKET_URL=https://tickets.nbis.se   # optional, this is the default
```

- `TICKET_PASSWORD` is accepted as an alias for `TICKET_API_KEY`.
- The mailbox id is the first number in a URL like `/mailbox/2/13`; the second
  number is the folder and is not needed.
- The user id must be an agent (`/users/profile/<id>`), not a customer
  (`/customers/<id>/edit`).
- `--config` needs PyYAML (`pip install pyyaml`).

## Dry run is the default

Nothing is sent unless you pass `--send`. Without it the script prints the
message and exits, so you can check it first.

## Send a new email

```bash
# 1. Dry run: prints the email, sends nothing
./send_email_through_bptickets.py --to jane@example.org --subject "Test message" --body-file msg.txt

# 2. Send it
./send_email_through_bptickets.py --to jane@example.org --subject "Test message" --body-file msg.txt --send
```

The script prints `sent to jane@example.org, conversation #<id>`. The
conversation is assigned to you and visible in the mailbox.

Other ways to give the body and options:

```bash
# Body from stdin
echo "Short note" | ./send_email_through_bptickets.py --to jane@example.org --subject "Note" --send

# File the conversation as Closed instead of leaving it Active
./send_email_through_bptickets.py --to jane@example.org --subject "FYI" --body-file msg.txt --status closed --send

# HTML body
./send_email_through_bptickets.py --to jane@example.org --subject "Report" --body-file msg.html --html --send
```

Plain-text bodies are HTML-escaped and keep their line breaks.

## Reply to an existing conversation

`--reply-to` takes the conversation id (the number in its URL, for example
`.../conversation/1234`). The reply is added as a message from you and emailed
to the conversation's customer. `--to` and `--subject` are not needed.

```bash
./send_email_through_bptickets.py --reply-to 1234 --body-file reply.txt --send

# Reply and close the conversation
./send_email_through_bptickets.py --reply-to 1234 --body-file reply.txt --status closed --send
```

For a reply, the conversation status stays unchanged unless you give `--status`.

## Use a YAML file

Put the message and its settings in a YAML file and pass it with `--config`.

New email, `mail.yaml`:

```yaml
to: jane@example.org
subject: Final notice
status: closed
body: |
  Dear Jane,

  Message text here.

  Best regards,
  BP-ops team
```

```bash
./send_email_through_bptickets.py --config mail.yaml          # dry run
./send_email_through_bptickets.py --config mail.yaml --send   # send
```

Reply, `reply.yaml` (the body is read from a file next to the YAML file):

```yaml
reply_to: 1234
body_file: reply_text.txt
```

```bash
./send_email_through_bptickets.py --config reply.yaml --send
```

Keys:

| Key | Meaning |
|---|---|
| `to` | recipient email (new email only) |
| `subject` | subject (new email only) |
| `body` | message text; use a block scalar (`body: \|`) |
| `body_file` | file with the message, relative to the YAML file (alternative to `body`) |
| `html` | `true` if the body is HTML (default `false`) |
| `status` | `active`, `pending` or `closed` |
| `reply_to` | conversation id; reply instead of creating a new conversation |
| `mailbox_id`, `user_id`, `url` | optional; override the environment variables |

Rules:
- Command-line options override the YAML values, for example
  `--config mail.yaml --subject "Other subject"`.
- The script refuses a YAML file that contains `api_key` or `password`, and
  unknown keys.
- There is no `send` key: sending always requires `--send` on the command line,
  so a YAML file cannot send by accident.

## Use from Python

```python
from send_email_through_bptickets import (
    TicketError, get_settings, reply_to_conversation, send_email,
)

settings = get_settings()   # reads the TICKET_* environment variables
try:
    cid = send_email(settings, "jane@example.org", "Subject", "Body text", status="closed")
    reply_to_conversation(settings, cid, "A follow-up message")
except TicketError as e:
    print("failed:", e)
```

## Options

| Option | Meaning |
|---|---|
| `--config YAML` | read the message and settings from a YAML file |
| `--to EMAIL` | recipient (new email) |
| `--subject TEXT` | subject (new email) |
| `--reply-to ID` | reply to this conversation instead of creating one |
| `--body-file FILE` | file with the message (default: stdin, unless `--config` gives a body) |
| `--html` | the body is HTML |
| `--status STATUS` | `active`, `pending` or `closed` |
| `--send` | actually send (default: dry run) |

## Troubleshooting

- **`Error: TICKET_API_KEY ... are required to use --send`**: set the
  environment variables above.
- **HTTP 401 or 403**: the API key is wrong or lacks permission.
- **HTTP 404 on a reply**: the conversation id does not exist or is not visible
  to the API key.
- **Sent, but not visible in the mailbox**: check the Closed folder or search for
  the subject. The conversation is assigned to `TICKET_USER_ID`, so it also
  appears under Mine.
