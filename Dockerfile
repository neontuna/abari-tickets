FROM ruby:3.4.7-slim

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        libusb-1.0-0 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

CMD ["bash"]
