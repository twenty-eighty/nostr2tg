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

config :nostr2tg, sync_interval_ms: sync_interval_ms

if config_env() == :prod do
  tg_bot = System.fetch_env!("N2TG_TG_BOT_TOKEN")
  tg_chat = System.fetch_env!("N2TG_TG_CHAT_ID")

  config :nostr2tg, tg: %{
           api_base: System.get_env("N2TG_TG_API_BASE", "https://api.telegram.org"),
           bot_token: tg_bot,
           chat_id: tg_chat,
           poll_timeout_ms: String.to_integer(System.get_env("N2TG_TG_POLL_TIMEOUT_MS", "10000")),
           prefix_text: System.get_env("N2TG_TG_PREFIX", "New Nostr article:")
         }
end
