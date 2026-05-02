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

group :development do
  gem "dotenv", "~> 3.1"
end
