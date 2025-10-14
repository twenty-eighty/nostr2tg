# Nostr2tg

Bridge Nostr long-form notes (kind 30023) into a Telegram channel. Fetch authors from a static list or a follow list (kind 3), format posts, and publish. Supports dry-run for safe testing.

## Configuration

Environment variables:

- `N2TG_TG_BOT_TOKEN` (required): Telegram bot token
- `N2TG_TG_CHAT_ID` (required): Target chat/channel ID (e.g. `-100xxxxxxxxxx`)
- `N2TG_MODE`: `authors` or `followlist` (default: `authors`)
- `N2TG_AUTHORS`: comma-separated author pubkeys (when `authors` mode)
- `N2TG_FOLLOWLIST_PUBKEY`: pubkey to read follow list from (when `followlist` mode)
- `N2TG_NOSTR_RELAYS`: comma-separated relay URLs
- `N2TG_TG_PREFIX`: prefix line for Telegram posts (default: `New Nostr article:`)
- `N2TG_LINK_NADDR_BASE`: base URL for naddr links (default: `https://njump.me/`)
- `N2TG_LINK_NIP05_BASE`: base URL for NIP-05 links
- `N2TG_SYNC_INTERVAL_MS`: sync interval in ms (default: `3600000`)
- `N2TG_TG_POLL_TIMEOUT_MS`: Telegram long-poll timeout in ms (default: `10000`)
- `N2TG_DRY_RUN`: set to `1` to simulate sends (no Telegram posts)
- `N2TG_SYNC_ALL_ON_EMPTY`: when no last Telegram post is found, set `1` to backfill all (default: `0` to start from now)

## Local development

```
mix deps.get
mix compile
MIX_ENV=dev mix dialyzer
```

Run with env vars set. For dry-run:

```
export N2TG_TG_BOT_TOKEN=xxx
export N2TG_TG_CHAT_ID=-100xxxxxxxxxx
export N2TG_DRY_RUN=1
iex -S mix
```

## Docker

Build and run locally:

```
docker build -t nostr2tg:local .
docker run --rm \
  -e N2TG_TG_BOT_TOKEN=xxx \
  -e N2TG_TG_CHAT_ID=-100xxxxxxxxxx \
  -e N2TG_DRY_RUN=1 \
  nostr2tg:local
```

## Deploy to Render.com

This repo includes `render.yaml` and a multi-stage `Dockerfile`.

1. Push the repo to GitHub.
2. In Render, create a new service → Worker → “Use existing render.yaml”.
3. Configure environment variables:
   - `N2TG_TG_BOT_TOKEN` (secret)
   - `N2TG_TG_CHAT_ID` (secret)
   - Optional: `N2TG_MODE`, `N2TG_AUTHORS`, `N2TG_FOLLOWLIST_PUBKEY`, `N2TG_NOSTR_RELAYS`, `N2TG_TG_PREFIX`, `N2TG_LINK_NADDR_BASE`, `N2TG_LINK_NIP05_BASE`, `N2TG_SYNC_INTERVAL_MS`, `N2TG_DRY_RUN`.
4. Deploy. The worker process runs `/app/start.sh` which launches the Erlang release.

### Notes

- Dry-run logs the full flow and skips Telegram network calls.
- Baseline timestamp initializes from recent bot updates, then persists in a DETS state file inside the container.

