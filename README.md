# abari-tickets

A small Ruby app that watches a "repairs" IMAP mailbox, prints qualifying
customer emails to a USB ESC/POS receipt printer, and exposes a small status
dashboard on `:4567`. Runs as one Sinatra/Puma process inside Docker on a
Raspberry Pi.

Built on [`net-imap`](https://github.com/ruby/net-imap) +
[`mail`](https://github.com/mikel/mail) for IMAP, `sinatra` + `puma` for the
dashboard, `rufus-scheduler` for in-process polling, and `sqlite3` for the
print-event log.

## Requirements

- Docker + Docker Compose (the canonical run target is on a Raspberry Pi
  with a USB receipt printer attached; the host kernel's `usblp` driver
  exposes it at `/dev/usb/lp0`).
- Ruby 3.4.7 (see `.ruby-version`) is only needed if you want to run things
  outside of Docker for editor tooling; the production stack runs entirely
  in the container.

## Setup

```bash
cp .env.example .env
# edit .env with your IMAP host + credentials, plus the new pipeline vars
docker compose build
```

### Required env vars


| Variable        | Description                                 | Default    |
| --------------- | ------------------------------------------- | ---------- |
| `IMAP_HOST`     | IMAP server hostname                        | (required) |
| `IMAP_USERNAME` | Login username (usually your email address) | (required) |
| `IMAP_PASSWORD` | Password or app password                    | (required) |
| `IMAP_PORT`     | IMAP port                                   | `993`      |
| `IMAP_SSL`      | Use TLS (1 is yes, anything else is no)     | `1`        |
| `IMAP_MAILBOX`  | Mailbox to read                             | `INBOX`    |
| `INBOX_LIMIT`   | How many recent messages to print           | `10`       |

The production pipeline (`docker compose up`) reads a few additional vars:

| Variable                 | Description                                              | Default                     |
| ------------------------ | -------------------------------------------------------- | --------------------------- |
| `IMAP_PROCESSED_MAILBOX` | Folder to move printed emails into (must already exist)  | `Repairs/Printed`           |
| `IMAP_SKIPPED_MAILBOX`   | Folder to move filtered-out emails into (must exist)     | `Repairs/Skipped`           |
| `POLL_INTERVAL_SECONDS`  | How often the scheduler polls IMAP                       | `180`                       |
| `PRINTER_DEVICE`         | usblp device node                                        | `/dev/usb/lp0`              |
| `BODY_MIN_CHARS`         | Reject emails with plaintext body shorter than this      | `5`                         |
| `BODY_MAX_CHARS`         | Reject emails with plaintext body longer than this       | `1500`                      |
| `DB_PATH`                | SQLite database file path inside the container           | `/app/data/repairs.sqlite3` |


### Gmail note

Gmail no longer accepts your account password over IMAP. You must:

1. Enable 2-Step Verification on the Google account.
2. Create an [App Password](https://myaccount.google.com/apppasswords) and use
  it as `IMAP_PASSWORD`.
3. Set `IMAP_HOST=imap.gmail.com`.

OAuth2 / `XOAUTH2` is a future enhancement; for now the app uses plain
`LOGIN` over TLS.

## Run

See [Production run](#production-run) below for the normal `docker compose up`
flow. There's no separate non-Docker run mode anymore.

## Docker (Raspberry Pi)

A minimal `Dockerfile` and `docker-compose.yml` are included so you can develop
on the Pi that the USB printer is connected to. The compose service mounts the
host's USB bus (`/dev/bus/usb`) and adds a USB cgroup rule so hot-plugged
devices (like the receipt printer) are usable inside the container.

Make sure `.env` exists (`cp .env.example .env`), then build the image:

```bash
docker compose build
```

Open a dev shell in the container (source is bind-mounted, so edits on the Pi
are live):

```bash
docker compose run --rm app
```

Sanity-check that the printer is visible from inside the container:

```bash
docker compose run --rm app bash -lc "ls -l /dev/usb/lp0"
```

If the host kernel has the `usblp` driver bound to the printer (the default on
Raspberry Pi OS), you can drive it by writing raw ESC/POS bytes to
`/dev/usb/lp0`. From IRB inside the container:

```ruby
File.binwrite("/dev/usb/lp0", "\x1b@hello, printer!\n\n\n\x1dV\x00")
```

If `device_cgroup_rules` is rejected on your kernel/cgroup combo, replace the
`devices:` and `device_cgroup_rules:` lines in `docker-compose.yml` with
`privileged: true`.

## Production run

The default `docker compose up` brings up a single container running a Sinatra
app on port `4567` plus an in-process scheduler that polls IMAP every
`POLL_INTERVAL_SECONDS`, filters out non-customer mail, prints qualifying
repair emails to the receipt printer, and moves each message into the
configured `Repairs/Printed` or `Repairs/Skipped` IMAP folder.

### One-time setup

1. Copy `.env.example` to `.env` and fill in IMAP credentials.
2. **Create the IMAP folders** the pipeline will move messages into. In Gmail,
   create labels named `Repairs/Printed` and `Repairs/Skipped` (or whatever
   you set `IMAP_PROCESSED_MAILBOX` / `IMAP_SKIPPED_MAILBOX` to). The pipeline
   does not auto-create them.

### Run

```bash
docker compose up -d
docker compose logs -f app
```

Visit `http://<pi-host>:4567` for the dashboard: emails printed today,
last printed / last skipped details, recent events, and printer status.
`/healthz` returns `ok`. `/events.json` returns the last 100 events.

### Filter

A message is **printed** unless any of these match:

- has a `List-Unsubscribe` header (bulk / list mail)
- has an `Auto-Submitted` header other than `no`
- has no `text/plain` part (HTML-only marketing)
- plaintext body is shorter than `BODY_MIN_CHARS` or longer than `BODY_MAX_CHARS`

Skip reasons are recorded so you can tune the thresholds in `.env`.

### Debug shell

The Dockerfile's default command is still `bash`, so the one-off form drops
you into a shell with the source bind-mounted:

```bash
docker compose run --rm app
```

## Troubleshooting

- `**missing required env var(s): ...`** — copy `.env.example` to `.env` and
fill in the missing values, or export them in your shell.
- `**IMAP login failed ... AUTHENTICATIONFAILED`** — wrong username/password.
For Gmail, make sure you're using an App Password and not your account
password.
- `**OpenSSL::SSL::SSLError: ... certificate verify failed (unable to get certificate CRL)**` — caused by a regression in `openssl` 3.3.0, which is the
version Ruby 3.4.7 ships with as a bundled gem. The `Gemfile` pins
`openssl >= 3.3.2` to work around it; if you still hit this, run
`bundle update openssl` and confirm `bundle exec ruby -ropenssl -e 'puts OpenSSL::VERSION'` reports `>= 3.3.2`.
- **Other `OpenSSL::SSL::SSLError`** — your IMAP host's certificate isn't
trusted by your system, or the host doesn't speak TLS on the port you set.
Verify `IMAP_HOST`/`IMAP_PORT` and update your system CA bundle if needed.
- **Connection hangs** — check that port 993 isn't blocked on your network.

