# syntax=docker/dockerfile:1
FROM ruby:3.4-slim

ENV APP_HOME=/app \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_FORCE_RUBY_PLATFORM=true \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    DB_PATH=/data/bot.db

WORKDIR ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libsqlite3-dev pkg-config ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

CMD ["bundle", "exec", "ruby", "bin/bot"]
