# abari-tickets

A small Ruby starter project. The first feature is a minimal inbox-reader script
that connects to a generic IMAP server and prints the most recent messages
(date, sender, subject). It uses `[net-imap](https://github.com/ruby/net-imap)`
for the protocol and the `[mail](https://github.com/mikel/mail)` gem to parse
each message.

## Requirements

- Ruby 3.4.7 (see `.ruby-version`)
- Bundler 2.x

## Setup

```bash
bundle install
cp .env.example .env
# edit .env with your IMAP host + credentials
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


### Gmail note

Gmail no longer accepts your account password over IMAP. You must:

1. Enable 2-Step Verification on the Google account.
2. Create an [App Password](https://myaccount.google.com/apppasswords) and use
  it as `IMAP_PASSWORD`.
3. Set `IMAP_HOST=imap.gmail.com`.

OAuth2 / `XOAUTH2` is a future enhancement; for now this script uses plain
`LOGIN` over TLS.

## Run

```bash
bundle exec bin/check_inbox
```

Example output:

```
Last 3 message(s) in INBOX on imap.gmail.com:
2026-04-30T09:14:22-04:00  alerts@example.com  [Alert] Build #1234 passed
2026-04-30T11:02:18-04:00  no-reply@github.com  [PR opened] Add inbox reader
2026-05-01T08:47:01-04:00  friend@example.com   lunch?
```

The script uses IMAP `EXAMINE` (read-only), so messages are **not** flagged as
Seen.

## Docker (Raspberry Pi)

A minimal `Dockerfile` and `docker-compose.yml` are included so you can develop
on the Pi that the USB printer is connected to. The compose service mounts the
host's USB bus (`/dev/bus/usb`) and adds a USB cgroup rule so hot-plugged
devices (like the receipt printer) are usable inside the container.

Make sure `.env` exists (`cp .env.example .env`), then:

```bash
docker compose build
docker compose run --rm app bundle exec bin/check_inbox
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

Port `4567` is pre-mapped for a future Sinatra/Rack app — once a web server is
running on `0.0.0.0:4567` inside the container, it's reachable at
`http://<pi-host>:4567`.

If `device_cgroup_rules` is rejected on your kernel/cgroup combo, replace the
`devices:` and `device_cgroup_rules:` lines in `docker-compose.yml` with
`privileged: true`.

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

