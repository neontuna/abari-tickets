# AGENTS.md

Notes for AI agents (and humans) working on this repo.

## Philosophy: keep it simple

This is a small, personal project. Optimize for readable, obvious code over
defensiveness or completeness.

- **Don't harden code that doesn't need hardening.** No retries, circuit
  breakers, exhaustive error taxonomies, or "enterprise" patterns unless a real
  problem demands them.
- **Don't add edge-case handling speculatively.** Wait until an edge case
  actually shows up. Crashing with a clear stack trace is fine for a tool that
  one person runs.
- **Prefer fewer files, fewer abstractions, fewer dependencies.** If a feature
  fits in one script, leave it in one script. Don't introduce a class hierarchy
  or a service layer for its own sake.
- **No tests yet.** Don't add a test framework or CI unless asked.
- **Match the existing style.** Plain Ruby, frozen string literals, small
  top-level scripts in `bin/`.

If you think something genuinely needs more rigor (e.g. real secrets handling,
something that will run unattended on a schedule), call it out and ask before
building it.

## What this repo is

A Ruby starter project running on a Raspberry Pi. Current scope:

- `bin/check_inbox` — connects to an IMAP server (read-only `EXAMINE`) and
  prints the most recent messages.
- A `Dockerfile` + `docker-compose.yml` set up to develop on the Pi, with
  `/dev/bus/usb` mounted so a USB receipt printer is reachable from inside the
  container.

Future-ish direction (don't pre-build any of this):
- A small Sinatra/Rack web app on port `4567` (already mapped in compose).
- Printing to the USB receipt printer.
- Some kind of "tickets" workflow tying email -> printer.

## Stack

- Ruby `3.4.7` (pinned via `.ruby-version` / `.tool-versions` / `Gemfile`).
- Bundler 2.x.
- Gems: `net-imap`, `mail`, `openssl >= 3.3.2` (works around a CRL regression
  in the openssl 3.3.0 that ships with Ruby 3.4.7), `dotenv` in development.

## Layout

```
bin/check_inbox        # main script (executable)
Gemfile / Gemfile.lock # deps
.env.example           # required env vars, copy to .env
Dockerfile             # ruby:3.4.7-slim + libusb
docker-compose.yml     # mounts /dev/bus/usb, exposes 4567
README.md              # user-facing setup + troubleshooting
```

## Running

```bash
bundle install
cp .env.example .env   # fill in IMAP_HOST / IMAP_USERNAME / IMAP_PASSWORD
bundle exec bin/check_inbox
```

Or in Docker on the Pi:

```bash
docker compose build
docker compose run --rm app bundle exec bin/check_inbox
```

See `README.md` for the full env var list and troubleshooting (Gmail App
Passwords, OpenSSL CRL error, etc.).

## Conventions

- Scripts in `bin/` are executable, start with `#!/usr/bin/env ruby` and
  `# frozen_string_literal: true`, and use `require "bundler/setup"`.
- Config comes from env vars, loaded via `dotenv` in development. Required
  vars are validated at the top of the script with a clear error.
- Keep `README.md` accurate when you change behavior or add env vars.
