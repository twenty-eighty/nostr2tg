import Config

config :nostr2tg,
  dry_run: (System.get_env("N2TG_DRY_RUN") in ["1", "true", "TRUE"]),
  sync_interval_ms: 3_600_000,
  sync_all_on_empty_channel: (System.get_env("N2TG_SYNC_ALL_ON_EMPTY") in ["1", "true", "TRUE"]),
  max_per_run: (case System.get_env("N2TG_MAX_PER_RUN") do
                  nil -> nil
                  "" -> nil
                  v ->
                    case Integer.parse(v) do
                      {i, ""} when i > 0 -> i
                      _ -> nil
                    end
                end),
  tg:
    %{
      api_base: "https://api.telegram.org",
      bot_token: System.get_env("N2TG_TG_BOT_TOKEN"),
      chat_id: System.get_env("N2TG_TG_CHAT_ID"),
      poll_timeout_ms: 10_000,
      prefix_text: System.get_env("N2TG_TG_PREFIX", "New Nostr article:"),
      throttle_ms: 1200
    },
  link:
    %{
      naddr_base: System.get_env("N2TG_LINK_NADDR_BASE", "https://njump.me/"),
      nip05_base: System.get_env("N2TG_LINK_NIP05_BASE", "https://example.com/nostr")
    },
  nostr:
    %{
      relays:
        case System.get_env("N2TG_NOSTR_RELAYS") do
          nil -> ["wss://relay.damus.io", "wss://nos.lol"]
          relays -> String.split(relays, ",", trim: true)
        end,
      # one of: "authors" or "followlist"
      mode: System.get_env("N2TG_MODE", "authors"),
      authors:
        case System.get_env("N2TG_AUTHORS") do
          nil -> []
          keys -> String.split(keys, ",", trim: true)
        end,
      followlist: System.get_env("N2TG_FOLLOWLIST_PUBKEY")
    }
