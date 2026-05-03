# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require "time"

# Tiny SQLite wrapper for the repairs pipeline. Schema is applied on first
# connection. One table, no migrations framework.
module DB
  SCHEMA = <<~SQL
    CREATE TABLE IF NOT EXISTS print_events (
      id            INTEGER PRIMARY KEY,
      occurred_at   TEXT    NOT NULL,
      action        TEXT    NOT NULL,
      reason        TEXT,
      sender        TEXT,
      subject       TEXT,
      body_excerpt  TEXT,
      message_id    TEXT,
      imap_uid      INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON print_events(occurred_at);
  SQL

  def self.connection
    @connection ||= begin
      path = ENV.fetch("DB_PATH")
      FileUtils.mkdir_p(File.dirname(path))
      conn = SQLite3::Database.new(path)
      conn.results_as_hash = true
      conn.execute_batch(SCHEMA)
      conn
    end
  end

  def self.record(action:, reason: nil, sender: nil, subject: nil,
                  body_excerpt: nil, message_id: nil, imap_uid: nil)
    connection.execute(
      "INSERT INTO print_events
        (occurred_at, action, reason, sender, subject, body_excerpt, message_id, imap_uid)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [Time.now.utc.iso8601, action, reason, sender, subject, body_excerpt, message_id, imap_uid]
    )
  end
end
