# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.7"

# Ruby 3.4.7 ships openssl 3.3.0, which has a regression where
# OpenSSL::SSL::SSLContext#set_params enables CRL checking and breaks TLS
# handshakes ("certificate verify failed (unable to get certificate CRL)").
# Pin >= 3.3.2 so net-imap's TLS handshake to gmail/etc. succeeds.
gem "openssl",  ">= 3.3.2"

gem "net-imap", "~> 0.6"
gem "mail",     "~> 2.8"

# Talk to the USB receipt printer via libusb-1.0 (the libusb-1.0-0
# runtime is installed in the Dockerfile). Lets us read printer status
# (paper out, cover open, etc.) on top of writing ESC/POS bytes.
gem "libusb",   "~> 0.7"

# Web dashboard + in-process scheduler.
gem "sinatra",         "~> 4.0"
gem "rackup",          "~> 2.1"
gem "puma",            "~> 6.4"
gem "rufus-scheduler", "~> 3.9"
gem "sqlite3",         "~> 2.0"

group :development do
  gem "dotenv", "~> 3.1"
end
