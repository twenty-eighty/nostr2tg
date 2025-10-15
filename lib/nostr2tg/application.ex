defmodule Nostr2tg.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    log_effective_config()
    children = [
      Nostr2tg.TelegramClient,
      Nostr2tg.Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nostr2tg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp log_effective_config do
    tg = Application.get_env(:nostr2tg, :tg, %{})
    nostr = Application.get_env(:nostr2tg, :nostr, %{})
    sync_ms = Application.get_env(:nostr2tg, :sync_interval_ms)
    dry = Application.get_env(:nostr2tg, :dry_run, false)
    sync_all = Application.get_env(:nostr2tg, :sync_all_on_empty_channel, false)
    max_per = Application.get_env(:nostr2tg, :max_per_run)
    link = Application.get_env(:nostr2tg, :link, %{})

    redacted_tg =
      tg
      |> Map.drop([:bot_token])
      |> Map.update(:chat_id, nil, fn v -> v end)

    Logger.info("Config: tg=#{inspect(redacted_tg)}")
    Logger.info("Config: nostr=#{inspect(nostr)}")
    Logger.info("Config: link=#{inspect(link)}")
    Logger.info("Config: sync_interval_ms=#{inspect(sync_ms)} dry_run=#{dry} sync_all_on_empty_channel=#{sync_all} max_per_run=#{inspect(max_per)}")
  end
end
