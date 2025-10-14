# syntax=docker/dockerfile:1

# ===== Builder =====
FROM elixir:1.17-slim AS builder

ENV MIX_ENV=prod
ENV LANG=C.UTF-8

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
       build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex/rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir -p config
COPY config/config.exs config/runtime.exs ./config/
RUN mix deps.compile

# Copy source
COPY lib ./lib
COPY README.md ./

# Build release
RUN mix compile && mix release

# ===== Runtime =====
FROM debian:bookworm-slim AS runtime

ENV LANG=C.UTF-8
ENV HOME=/app
ENV MIX_ENV=prod

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
       ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/* \
    && adduser --system --group --home /app app

WORKDIR /app/nostr2tg

COPY --from=builder /app/_build/prod/rel/nostr2tg ./
COPY bin/start.sh /app/start.sh
RUN chown -R app:app /app && chmod +x /app/start.sh

USER app

ENTRYPOINT ["/app/start.sh"]

