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

A small Ruby app running on a Raspberry Pi that watches a "repairs" IMAP
mailbox and prints qualifying customer emails to a USB ESC/POS receipt
printer. There's a tiny Sinatra dashboard at `:4567` for status.

The app is one process, in one container:

- **Sinatra** serves the dashboard.
- **rufus-scheduler** runs in a thread inside the same Puma process and polls
  IMAP every `POLL_INTERVAL_SECONDS`.
- Each poll: fetch all messages in `INBOX`, check printer status; if the
  printer isn't ready, record one `deferred` event and bail (messages stay
  in INBOX, retried next poll). Otherwise run each message through
  `EmailFilter`, print the ones that pass via the `Printer` class (libusb
  bulk transfers, ESC/POS), record an event row in SQLite, then
  `IMAP MOVE` the message into `Repairs/Printed` or `Repairs/Skipped`.
  Inbox stays empty between polls.

Architecture (don't add pieces not on this picture without asking):

```
rufus  ->  InboxProcessor  ->  IMAP (fetch/move)
                            ->  EmailFilter (decide)
                            ->  Printer (libusb -> USB receipt printer)
                            ->  DB (SQLite print_events)
Sinatra (:4567)             ->  Printer.status (live status card)
                            ->  DB
```

There is **no Rails, no Sidekiq, no Redis, no cron, no host-side daemon**.
That has been deliberately considered and rejected as overkill. If you find
yourself reaching for any of them, stop and check with the user first.

## Stack

- Ruby `3.4.7` (pinned via `.ruby-version` / `.tool-versions` / `Gemfile`).
- Bundler 2.x.
- Web: `sinatra`, `rackup`, `puma`. Single Puma process, default thread pool.
- Scheduler: `rufus-scheduler` (in-process, single thread).
- Storage: `sqlite3`, file lives at `DB_PATH` on a named docker volume so it
  survives rebuilds. No migration framework; schema is `CREATE TABLE IF NOT
  EXISTS` applied on every boot from `lib/db.rb`.
- Mail: `net-imap`, `mail`, `openssl >= 3.3.2` (works around a CRL regression
  in the openssl 3.3.0 that ships with Ruby 3.4.7).
- Dev only: `dotenv`.

## Layout

```
app.rb                   # Sinatra app: routes + scheduler hook
config.ru                # rackup entrypoint
views/dashboard.erb      # plain HTML/ERB dashboard, no JS
lib/printer.rb           # ESC/POS driver (write/feed/cut, block form auto-cuts)
lib/email_filter.rb      # decide(mail) -> [:print] | [:skip, reason]
lib/inbox_processor.rb   # one poll cycle: fetch -> filter -> print -> move
lib/db.rb                # SQLite handle + DB.record helper, schema on boot
bin/                     # reserved for future executable scripts (currently empty)
Gemfile / Gemfile.lock   # deps
.env / .env.example      # config
Dockerfile               # ruby:3.4.7-slim + native build + libusb + libssl + libsqlite3
docker-compose.yml       # default command runs puma; mounts /dev/usb/lp0
README.md                # user-facing setup, env vars, troubleshooting
```

## Running

The default `docker compose up` brings up the production stack:

```bash
docker compose up -d
docker compose logs -f app
# dashboard at http://<pi-host>:4567
```

For a debug shell (Dockerfile `CMD` is still `bash`):

```bash
docker compose run --rm app                                 # interactive bash
docker compose run --rm app bundle exec irb -Ilib -rprinter # poke the printer
```

The `Repairs/Printed` and `Repairs/Skipped` IMAP folders must exist on the
server before the first poll fires. The processor will not auto-create them.

## Conventions

- **Ruby files** start with `# frozen_string_literal: true`. Any future
  scripts added to `bin/` should also start with `#!/usr/bin/env ruby` and
  `require "bundler/setup"`.
- **Reusable code lives in `lib/`** as small modules or classes (one
  responsibility each). Don't introduce a service layer or directory of
  base classes; keep the tree shallow.
- **Config comes from env vars**, loaded via `dotenv` in development and via
  compose's `env_file: .env` in production. Add new vars to both `.env.example`
  and the README env-var table.
- **No schema migrations.** `lib/db.rb` uses `CREATE TABLE IF NOT EXISTS` and
  is reapplied on every boot. If you need a column, add it to the schema and
  to any code that selects/inserts; for an existing dev DB you can wipe the
  `repairs_data` volume.
- **Filter rules live in `lib/email_filter.rb`.** When tuning what gets
  printed vs skipped, that's the single place. Each rule should produce a
  human-readable skip reason — the dashboard surfaces them so the user can
  tune thresholds without spelunking through code.
- **Printer is bidirectional via libusb.** `lib/printer.rb` opens the USB
  Printer Class device directly (VID/PID hardcoded), claims the printer
  interface with `auto_detach_kernel_driver = true` so the kernel `usblp`
  driver gets out of the way, and uses the bulk OUT endpoint for ESC/POS
  bytes plus the bulk IN endpoint for `DLE EOT n` real-time status reads.
  `Printer.status` returns a `Printer::Status` struct (`online`, `paper`,
  `cover_open`, `error`, plus the raw bytes for debugging).
- **Print jobs are gated on printer status.** At the top of each poll
  cycle, after fetching the inbox UID list, `InboxProcessor` calls
  `Printer.status` once and bails with a single `deferred` event if it's
  not ready. Messages stay in INBOX and retry next poll. Per-message
  status checks are deliberately not added (noisy and rarely useful).
- **Errors in the poll loop must not kill the scheduler.** The `every` block
  in `app.rb` catches `StandardError` and `warn`s. Errors inside
  `process_one` (e.g. a single bad message) do propagate up and abort the
  current poll — that's intentional; the message stays in INBOX and gets
  retried on the next poll.
- **Keep `README.md` accurate** when you change behavior, env vars, or
  required IMAP folders.

## Things that have been deliberately deferred

These have come up and been ruled out for now. Don't add them without asking:

- Tests / CI / linters.
- Authentication on the dashboard (it's on a trusted LAN).
- Photo / attachment printing (customers occasionally attach photos; ignored
  for now, only the plaintext body is printed).
- Configurable printer VID/PID (one printer on one Pi; if it ever changes,
  edit the constants in `lib/printer.rb`).
- Long-lived shared printer USB handle. Open/close per print job and per
  status read is fine at our cadence (~100 ms each).
- Retries, dead-lettering, deduplication, rate limiting.
- Pretty receipt formatting (bold/centered/barcodes/QR). The receipt is
  plain text and the printer hardware-wraps long lines. Add styling only
  when there's a concrete UX reason.
