defmodule Nostr2tg.Scheduler do
  @moduledoc false

  use GenServer
  require Logger

  alias Nostr2tg.{Nostr, TelegramClient, LinkBuilder}

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_args), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    state = %{last_ts: 0, halt_until_pinned: false}
    st = init_last_ts_from_pinned(state)
    schedule_next(0)
    {:ok, st}
  end

  @impl true
  def handle_info(:sync, state) do
    Logger.info("Starting sync tick")
    state =
      if Map.get(state, :halt_until_pinned, false) do
        Logger.warning("No pinned message found in non-empty channel; halting publishing until a message is pinned")
        state
      else
        try do
          do_sync(state)
        rescue
          e ->
            Logger.error("Sync tick crashed: #{inspect(e)}")
            state
        end
      end
    schedule_next(sync_interval())
    Logger.info("Finished sync tick")
    {:noreply, state}
  end

  defp sync_interval do
    Application.get_env(:nostr2tg, :sync_interval_ms, 3_600_000)
  end

  defp schedule_next(ms) do
    next_at = DateTime.add(DateTime.utc_now(), div(ms, 1000), :second)
    Logger.debug("Next sync scheduled at #{Calendar.strftime(next_at, "%Y-%m-%d %H:%M:%S")} (in #{ms} ms)")
    Process.send_after(self(), :sync, ms)
  end

  defp do_sync(%{last_ts: last_ts} = state) do
    cfg = Application.fetch_env!(:nostr2tg, :nostr)
    relays = Map.fetch!(cfg, :relays)

    query_since =
      case last_ts do
        int when is_integer(int) -> int + 1
        _ -> 0
      end

    Logger.info("Last published ts: #{last_ts}; querying since: #{query_since}; relays: #{inspect(relays)}")

    with {:ok, authors} <- Nostr.authors_from_mode(cfg),
         {:ok, events} <- Nostr.list_article_events_by_authors(query_since, authors, relays) do
      Logger.info("Found #{length(events)} events since #{query_since} for #{length(authors)} authors")
      filtered = events
      sorted = Enum.sort_by(filtered, &effective_published_at/1, :asc)

      profiles =
        case Nostr.fetch_profiles(Enum.uniq(Enum.map(sorted, & &1["pubkey"])), relays) do
          {:ok, map} -> map
          _ -> %{}
        end

      # Drop anything at or before baseline to avoid duplicates even if relays resend old events
      eligible = Enum.filter(sorted, fn ev -> effective_published_at(ev) > last_ts end)

      # Respect max_per_run: take oldest first
      take_n =
        case Application.get_env(:nostr2tg, :max_per_run) do
          i when is_integer(i) and i > 0 -> i
          _ -> length(eligible)
        end

      batch = Enum.take(eligible, take_n)

      throttle_ms = Map.get(Application.fetch_env!(:nostr2tg, :tg), :throttle_ms, 1200)

      {new_last_ts, last_message_id} =
      Enum.reduce_while(batch, {last_ts, nil}, fn ev, {acc_last, last_mid} ->
        pub_at = effective_published_at(ev)
        key = article_key(ev)
        last = acc_last

        cond do
          not is_integer(pub_at) ->
            Logger.warning("Skipping event without valid published_at: #{inspect(ev["id"])}")
            {:cont, {acc_last, last_mid}}

          pub_at <= last ->
            Logger.info("Article published_at=#{pub_at} <= last=#{last}, skipping")
            {:cont, {acc_last, last_mid}}

          true ->
            profile = Map.get(profiles, ev["pubkey"], %{})
            text = format_post(ev, profile)
            Logger.info("Publishing article #{key} at published_at=#{pub_at}")
            if not Application.get_env(:nostr2tg, :dry_run, false) do
              Logger.debug("Post text:\n" <> text)
            end
            case TelegramClient.send_message(text) do
              {:ok, resp} ->
                mark_announced_if_not_dry(key, pub_at)
                message_id = get_in(resp, ["result", "message_id"]) || get_in(resp, [:result, :message_id])
                # Throttle between messages
                if throttle_ms > 0, do: Process.sleep(throttle_ms)
                {:cont, {max(pub_at, acc_last), if(is_integer(message_id), do: message_id, else: last_mid)}}
              {:error, {:status, 429, body}} ->
                Logger.error("Rate limited by Telegram (429): #{inspect(body)}")
                # On rate limit, pin last successfully sent message (if any) and stop batch to avoid duplicates
                if not Application.get_env(:nostr2tg, :dry_run, false) and is_integer(last_mid) do
                  tg = Application.fetch_env!(:nostr2tg, :tg)
                  chat_id = Map.fetch!(tg, :chat_id)
                  do_unpin_pin(chat_id, last_mid)
                end
                # Honor retry_after if present
                retry = extract_retry_after_seconds(body) || 0
                if retry > 0 do
                  Logger.info("Sleeping for #{retry}s due to rate-limit")
                  Process.sleep(retry * 1000 + 200)
                end
                {:halt, {acc_last, last_mid}}
              {:error, reason} ->
                Logger.error("Failed to send TG message: #{inspect(reason)}")
                {:cont, {acc_last, last_mid}}
            end
        end
      end)

      # After batch, pin last sent message if any
      if not Application.get_env(:nostr2tg, :dry_run, false) and is_integer(last_message_id) do
        tg = Application.fetch_env!(:nostr2tg, :tg)
        chat_id = Map.fetch!(tg, :chat_id)
        do_unpin_pin(chat_id, last_message_id)
      end

      %{state | last_ts: new_last_ts}
    else
      {:error, reason} ->
        Logger.error("Sync error: #{inspect(reason)}")
        state
    end
  end

  defp init_last_ts_from_pinned(state) do
    Logger.info("Initializing baseline from pinned message")
    case TelegramClient.get_chat_info() do
      {:ok, %{"result" => %{"pinned_message" => %{"date" => date, "text" => text}}}} when is_integer(date) and is_binary(text) ->
        pub_ts = extract_published_from_text(text) || date
        Logger.info("Pinned message baseline: published=#{pub_ts} (message date=#{date})")
        %{state | last_ts: pub_ts}
      _ ->
        # Determine if channel has messages by checking recent updates for this chat id
        tg = Application.fetch_env!(:nostr2tg, :tg)
        chat_id = Map.get(tg, :chat_id)
        non_empty? =
          case TelegramClient.get_updates(nil) do
            {:ok, updates} ->
              Enum.any?(updates, fn u ->
                case u do
                  %{"channel_post" => %{"chat" => %{"id" => id}}} -> to_string(id) == to_string(chat_id)
                  _ -> false
                end
              end)
            _ -> false
          end

        if non_empty? do
          Logger.warning("Channel appears non-empty but has no pinned message; halting until a baseline is pinned")
          %{state | halt_until_pinned: true}
        else
          if Application.get_env(:nostr2tg, :sync_all_on_empty_channel, false) do
            Logger.info("Empty channel and no pinned message. sync_all_on_empty_channel=true; syncing all.")
            state
          else
            now = System.system_time(:second)
            Logger.info("Empty channel and no pinned message. Starting from now=#{now}.")
            %{state | last_ts: now}
          end
        end
    end
  end

  # No longer used (was for baseline via getUpdates)

  # Pinned message is updated per-article to the last posted item

  defp format_post(event, profile) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    prefix = Map.get(tg, :prefix_text, "")

    {title, summary} = extract_title_summary(event)

    link = LinkBuilder.build_article_link(event, profile)

    # Use HTML formatting for Telegram
    title_html = html_escape(String.trim(title))
    summary_html = html_escape(String.trim(summary))
    bold_title = "<b>" <> title_html <> "</b>"
    italic_summary = "<i>" <> summary_html <> "</i>"

    published_line = format_published_line(event)

    [String.trim(prefix) <> " " <> bold_title, italic_summary, link, published_line]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp extract_title_summary(%{"tags" => tags} = event) do
    title =
      case Enum.find(tags, fn t -> match?(["title", _], t) end) do
        ["title", t] -> t
        _ ->
          case event["content"] do
            bin when is_binary(bin) ->
              String.split(bin, ["\r\n", "\n"], trim: true) |> Enum.at(0, "(no title)")
            _ -> "(no title)"
          end
      end

    summary =
      case Enum.find(tags, fn t -> match?(["summary", _], t) end) do
        ["summary", s] -> s
        _ ->
          case event["content"] do
            bin when is_binary(bin) ->
              String.split(bin, ["\r\n", "\n"], trim: true) |> Enum.at(1, "")
            _ -> ""
          end
      end

    {title, summary}
  end

  # Minimal HTML escaping
  defp html_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp format_published_line(event) do
    ts = effective_published_at(event)
    case ts do
      int when is_integer(int) ->
        dt = DateTime.from_unix!(int)
        formatted = Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
        "Published: " <> formatted
      _ -> ""
    end
  end

  defp effective_published_at(%{"tags" => tags} = ev) do
    case Enum.find(tags, fn t -> match?(["published_at", _], t) end) do
      ["published_at", ts] when is_binary(ts) ->
        case Integer.parse(ts) do
          {int, ""} -> int
          _ -> ev["created_at"]
        end
      ["published_at", int] when is_integer(int) -> int
      _ -> ev["created_at"]
    end
  end

  defp effective_published_at(ev), do: ev["created_at"]

  defp article_key(%{"kind" => kind, "pubkey" => pk, "tags" => tags}) do
    case Enum.find(tags, fn t -> match?(["d", _], t) end) do
      ["d", ident] when is_binary(ident) -> "#{kind}:#{pk}:#{ident}"
      _ -> nil
    end
  end

  defp article_key(_), do: nil

  defp mark_announced_if_not_dry(key, pub_at) when is_binary(key) and is_integer(pub_at) do
    if Application.get_env(:nostr2tg, :dry_run, false) do
      :ok
    else
      # No persistent store; rely on time window and pinned ts.
      :ok
    end
  end

  defp extract_published_from_text(text) when is_binary(text) do
    # Expect a trailing line like: "Published: YYYY-MM-DD HH:MM:SS"
    case Regex.run(~r/Published:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*\z/, text) do
      [_, ts_str] ->
        with {:ok, dt, _} <- DateTime.from_iso8601(String.replace(ts_str, " ", "T") <> "Z") do
          DateTime.to_unix(dt)
        else
          _ -> nil
        end
      _ -> nil
    end
  end

  defp do_unpin_pin(chat_id, message_id) do
    _ = TelegramClient.unpin_all_chat_messages(chat_id)
    case TelegramClient.pin_chat_message(chat_id, message_id) do
      {:ok, %{"ok" => true}} -> Logger.info("Pinned message #{message_id} as baseline")
      {:ok, other} -> Logger.warning("Unexpected pinChatMessage response: #{inspect(other)}")
      {:error, reason} -> Logger.error("Failed to pin message #{message_id}: #{inspect(reason)}")
    end
  end

  defp extract_retry_after_seconds(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"parameters" => %{"retry_after" => s}}} when is_integer(s) -> s
      _ -> nil
    end
  end
  defp extract_retry_after_seconds(_), do: nil

  # no-op helpers removed
end
