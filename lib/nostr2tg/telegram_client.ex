defmodule Nostr2tg.TelegramClient do
  @moduledoc false

  use GenServer
  require Logger

  @type send_result :: {:ok, map()} | {:error, term()}
  @type get_updates_result :: {:ok, [map()]} | {:error, term()}
  @type api_result :: {:ok, map()} | {:error, term()}

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_args), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, %{}}

  @spec send_message(String.t()) :: send_result()
  def send_message(text) when is_binary(text),
    do: GenServer.call(__MODULE__, {:send_message, text}, 30_000)

  @spec get_updates(non_neg_integer() | nil) :: get_updates_result()
  def get_updates(offset \\ nil), do: GenServer.call(__MODULE__, {:get_updates, offset}, 30_000)

  @spec get_chat_info() :: api_result()
  def get_chat_info, do: GenServer.call(__MODULE__, :get_chat_info, 30_000)

  @spec edit_message_text(integer() | String.t(), integer(), String.t()) :: api_result()
  def edit_message_text(chat_id, message_id, text),
    do: GenServer.call(__MODULE__, {:edit_message_text, chat_id, message_id, text}, 30_000)

  @spec pin_chat_message(integer() | String.t(), integer()) :: api_result()
  def pin_chat_message(chat_id, message_id),
    do: GenServer.call(__MODULE__, {:pin_chat_message, chat_id, message_id}, 30_000)

  @spec unpin_chat_message(integer() | String.t(), integer()) :: api_result()
  def unpin_chat_message(chat_id, message_id),
    do: GenServer.call(__MODULE__, {:unpin_chat_message, chat_id, message_id}, 30_000)

  @spec unpin_all_chat_messages(integer() | String.t()) :: api_result()
  def unpin_all_chat_messages(chat_id),
    do: GenServer.call(__MODULE__, {:unpin_all_chat_messages, chat_id}, 30_000)

  @impl true
  def handle_call({:send_message, text}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    dry? = Application.get_env(:nostr2tg, :dry_run, false)

    if dry? do
      Logger.info(
        "[DRY-RUN] Would send Telegram message: #{inspect(String.slice(text, 0, 200))}..."
      )

      {:reply, {:ok, %{"ok" => true, "result" => %{"dry_run" => true}}}, state}
    else
      case tg_post("sendMessage", %{
             chat_id: Map.fetch!(tg, :chat_id),
             text: text,
             parse_mode: "HTML",
             disable_web_page_preview: false
           }) do
        {:ok, resp} -> {:reply, {:ok, resp}, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:get_updates, offset}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    params = %{timeout: div(Map.get(tg, :poll_timeout_ms, 10_000), 1000)}
    params = if offset, do: Map.put(params, :offset, offset), else: params

    case tg_get("getUpdates", params) do
      {:ok, %{"result" => result}} -> {:reply, {:ok, result}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_chat_info, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)

    case tg_get("getChat", %{chat_id: Map.fetch!(tg, :chat_id)}) do
      {:ok, resp = %{"ok" => true}} -> {:reply, {:ok, resp}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:edit_message_text, chat_id, message_id, text}, _from, state) do
    case tg_post("editMessageText", %{
           chat_id: chat_id,
           message_id: message_id,
           text: text,
           parse_mode: "HTML"
         }) do
      {:ok, resp = %{"ok" => true}} -> {:reply, {:ok, resp}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:pin_chat_message, chat_id, message_id}, _from, state) do
    case tg_post("pinChatMessage", %{chat_id: chat_id, message_id: message_id}) do
      {:ok, resp = %{"ok" => true}} -> {:reply, {:ok, resp}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unpin_chat_message, chat_id, message_id}, _from, state) do
    case tg_post("unpinChatMessage", %{chat_id: chat_id, message_id: message_id}) do
      {:ok, resp = %{"ok" => true}} -> {:reply, {:ok, resp}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unpin_all_chat_messages, chat_id}, _from, state) do
    case tg_post("unpinAllChatMessages", %{chat_id: chat_id}) do
      {:ok, resp = %{"ok" => true}} -> {:reply, {:ok, resp}, state}
      {:ok, other} -> {:reply, {:error, {:bad_response, other}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # --- Private helpers ---
  defp tg_base_url do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    Map.fetch!(tg, :api_base) <> "/bot" <> Map.fetch!(tg, :bot_token)
  end

  defp tg_post(method, payload) do
    url = tg_base_url() <> "/" <> method
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)

    case Req.post(url: url, headers: headers, body: body) do
      {:ok, %{status: status, body: resp}} when status in 200..299 -> normalize_json_ok(resp)
      {:ok, %{status: status, body: resp}} -> {:error, {:status, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tg_get(method, params) do
    url = tg_base_url() <> "/" <> method <> "?" <> URI.encode_query(params)

    case Req.get(url: url) do
      {:ok, %{status: status, body: resp}} when status in 200..299 -> normalize_json_ok(resp)
      {:ok, %{status: status, body: resp}} -> {:error, {:status, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_json_ok(resp) do
    case resp do
      %{"ok" => _} = map ->
        {:ok, map}

      bin when is_binary(bin) ->
        case Jason.decode(bin) do
          {:ok, %{"ok" => _} = map} -> {:ok, map}
          other -> other
        end

      other ->
        {:error, {:bad_response, other}}
    end
  end
end
