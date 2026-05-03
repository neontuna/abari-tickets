# frozen_string_literal: true

require "net/imap"
require "mail"
require_relative "printer"
require_relative "email_filter"
require_relative "db"

# Pulls all messages from the configured INBOX, decides print vs skip for
# each, prints the printable ones, then MOVEs each message to either the
# "processed" or "skipped" mailbox so the inbox stays empty between polls.
module InboxProcessor
  def self.run
    host    = ENV.fetch("IMAP_HOST")
    port    = Integer(ENV.fetch("IMAP_PORT", "993"))
    ssl     = ENV["IMAP_SSL"]&.to_i == 1
    user    = ENV.fetch("IMAP_USERNAME")
    pass    = ENV.fetch("IMAP_PASSWORD")
    inbox   = ENV.fetch("IMAP_MAILBOX", "INBOX")
    printed = ENV.fetch("IMAP_PROCESSED_MAILBOX")
    skipped = ENV.fetch("IMAP_SKIPPED_MAILBOX")

    imap = Net::IMAP.new(host, port: port, ssl: ssl)
    imap.login(user, pass)
    imap.select(inbox)

    uids = imap.uid_search(["ALL"])
    return if uids.empty?

    status = Printer.status
    unless status.ok?
      DB.record(
        action: "deferred",
        reason: "printer not ready: #{status.summary} (#{uids.size} waiting)"
      )
      return
    end

    uids.each { |uid| process_one(imap, uid, printed_dest: printed, skipped_dest: skipped) }
  ensure
    begin
      imap&.logout
    rescue StandardError
      # best-effort
    end
    begin
      imap&.disconnect
    rescue StandardError
      # best-effort
    end
  end

  def self.process_one(imap, uid, printed_dest:, skipped_dest:)
    raw  = imap.uid_fetch(uid, "RFC822").first.attr["RFC822"]
    mail = Mail.read_from_string(raw)

    sender  = Array(mail.from).first
    subject = mail.subject
    msg_id  = mail.message_id

    decision, reason = EmailFilter.decide(mail)
    if decision == :print
      body = EmailFilter.plain_body(mail)
      Printer.open(ENV.fetch("PRINTER_DEVICE", Printer::DEFAULT_DEVICE)) do |p|
        p.write("REPAIR REQUEST\n")
        p.write("#{Time.now.strftime('%Y-%m-%d %H:%M')}\n")
        p.write("From: #{sender}\n")
        p.write("Subject: #{subject}\n\n")
        p.write("#{body}\n")
      end
      DB.record(action: "printed", sender: sender, subject: subject,
                body_excerpt: excerpt(mail), message_id: msg_id, imap_uid: uid)
      imap.uid_move(uid, printed_dest)
    else
      DB.record(action: "skipped", reason: reason, sender: sender, subject: subject,
                body_excerpt: excerpt(mail), message_id: msg_id, imap_uid: uid)
      imap.uid_move(uid, skipped_dest)
    end
  end

  def self.excerpt(mail)
    body = EmailFilter.plain_body(mail) || ""
    body[0, 200]
  end
end
