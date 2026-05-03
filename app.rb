# frozen_string_literal: true

require "json"
require "sinatra/base"
require "rufus-scheduler"

begin
  require "dotenv"
  Dotenv.load
rescue LoadError
  # dotenv is dev-only; in production rely on real ENV from .env via compose.
end

require_relative "lib/db"
require_relative "lib/inbox_processor"

class RepairsApp < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, 4567
  set :views, File.expand_path("views", __dir__)

  configure do
    DB.connection
    set :booted_at, Time.now

    scheduler = Rufus::Scheduler.new
    interval  = Integer(ENV.fetch("POLL_INTERVAL_SECONDS", "180"))
    scheduler.every "#{interval}s", first_in: "5s" do
      begin
        InboxProcessor.run
      rescue StandardError => e
        warn "[poll] error: #{e.class}: #{e.message}"
      end
    end
    set :scheduler, scheduler
  end

  get "/healthz" do
    "ok"
  end

  get "/" do
    @today_count  = DB.connection.execute(
      "SELECT COUNT(*) AS n FROM print_events
        WHERE action = 'printed' AND date(occurred_at) = date('now')"
    ).first["n"]
    @last_printed = DB.connection.execute(
      "SELECT * FROM print_events WHERE action='printed'
        ORDER BY id DESC LIMIT 1"
    ).first
    @last_skipped = DB.connection.execute(
      "SELECT * FROM print_events WHERE action='skipped'
        ORDER BY id DESC LIMIT 1"
    ).first
    @recent       = DB.connection.execute(
      "SELECT * FROM print_events ORDER BY id DESC LIMIT 25"
    )
    @printer_device = ENV.fetch("PRINTER_DEVICE", "/dev/usb/lp0")
    @printer_ok     = File.writable?(@printer_device)
    @booted_at      = settings.booted_at
    @poll_interval  = Integer(ENV.fetch("POLL_INTERVAL_SECONDS", "180"))
    erb :dashboard
  end

  get "/events.json" do
    content_type :json
    rows = DB.connection.execute(
      "SELECT * FROM print_events ORDER BY id DESC LIMIT 100"
    )
    rows.to_json
  end
end
