import Config

level =
  case System.get_env("N2TG_LOG_LEVEL") || System.get_env("LOG_LEVEL") do
    lvl when is_binary(lvl) ->
      case String.downcase(lvl) do
        "debug" -> :debug
        "info" -> :info
        "warn" -> :warn
        "warning" -> :warn
        "error" -> :error
        _ -> :info
      end
    _ -> :info
  end

config :logger, level: level

sync_interval_ms =
  case System.get_env("N2TG_SYNC_INTERVAL_MS") do
    nil -> 3_600_000
    v ->
      case Integer.parse(v) do
        {i, ""} when i > 0 -> i
        _ -> 3_600_000
      end
  end

dry_run? = System.get_env("N2TG_DRY_RUN") in ["1", "true", "TRUE"]
sync_all_on_empty? = System.get_env("N2TG_SYNC_ALL_ON_EMPTY") in ["1", "true", "TRUE"]

max_per_run =
  case System.get_env("N2TG_MAX_PER_RUN") do
    nil -> nil
    "" -> nil
    v ->
      case Integer.parse(v) do
        {i, ""} when i > 0 -> i
        _ -> nil
      end
  end

tg_bot = System.get_env("N2TG_TG_BOT_TOKEN")
tg_chat = System.get_env("N2TG_TG_CHAT_ID")

tg_config = %{
  api_base: System.get_env("N2TG_TG_API_BASE", "https://api.telegram.org"),
  bot_token: tg_bot,
  chat_id: tg_chat,
  poll_timeout_ms: String.to_integer(System.get_env("N2TG_TG_POLL_TIMEOUT_MS", "10000")),
  prefix_text: System.get_env("N2TG_TG_PREFIX", "New Nostr article:"),
  throttle_ms: String.to_integer(System.get_env("N2TG_TG_THROTTLE_MS", "1200"))
}

link_config = %{
  naddr_base: System.get_env("N2TG_LINK_NADDR_BASE", "https://njump.me/"),
  nip05_base: System.get_env("N2TG_LINK_NIP05_BASE", "https://example.com/nostr")
}

nostr_relays =
  case System.get_env("N2TG_NOSTR_RELAYS") do
    nil -> ["wss://relay.damus.io", "wss://nos.lol"]
    relays -> String.split(relays, ",", trim: true)
  end

nostr_mode = System.get_env("N2TG_MODE", "authors")

nostr_authors =
  case System.get_env("N2TG_AUTHORS") do
    nil -> []
    keys -> String.split(keys, ",", trim: true)
  end

nostr_config = %{
  relays: nostr_relays,
  mode: nostr_mode,
  authors: nostr_authors,
  followlist: System.get_env("N2TG_FOLLOWLIST_PUBKEY")
}

config :nostr2tg,
  dry_run: dry_run?,
  sync_interval_ms: sync_interval_ms,
  sync_all_on_empty_channel: sync_all_on_empty?,
  max_per_run: max_per_run,
  tg: tg_config,
  link: link_config,
  nostr: nostr_config
