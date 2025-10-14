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
  def send_message(text) when is_binary(text), do: GenServer.call(__MODULE__, {:send_message, text}, 30_000)

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

  @impl true
  def handle_call({:send_message, text}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    dry? = Application.get_env(:nostr2tg, :dry_run, false)

    if dry? do
      Logger.info("[DRY-RUN] Would send Telegram message: #{inspect(String.slice(text, 0, 200))}...")
      {:reply, {:ok, %{"ok" => true, "result" => %{"dry_run" => true}}}, state}
    else
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    chat_id = Map.fetch!(tg, :chat_id)

    url = base <> "/bot" <> token <> "/sendMessage"
    body = Jason.encode!(%{chat_id: chat_id, text: text, parse_mode: "HTML", disable_web_page_preview: false})
    headers = [{"content-type", "application/json"}]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: status, body: resp}} when status in 200..299 ->
        {:reply, {:ok, Jason.decode!(resp)}, state}

      {:ok, %Finch.Response{status: status, body: resp}} ->
        Logger.error("Telegram sendMessage failed: #{status} #{inspect(resp)}")
        {:reply, {:error, {:status, status, resp}}, state}

      {:error, reason} ->
        Logger.error("Telegram sendMessage error: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
    end
  end

  @impl true
  def handle_call({:get_updates, offset}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    url = base <> "/bot" <> token <> "/getUpdates"
    params = %{timeout: div(Map.get(tg, :poll_timeout_ms, 10_000), 1000)}
    params = if offset, do: Map.put(params, :offset, offset), else: params
    full_url = url <> "?" <> URI.encode_query(params)

    request = Finch.build(:get, full_url)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: status, body: resp}} when status in 200..299 ->
        with {:ok, %{"ok" => true, "result" => result}} <- Jason.decode(resp) do
          {:reply, {:ok, result}, state}
        else
          _ -> {:reply, {:error, :bad_response}, state}
        end

      {:ok, %Finch.Response{status: status, body: resp}} ->
        {:reply, {:error, {:status, status, resp}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_chat_info, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    chat_id = Map.fetch!(tg, :chat_id)
    url = base <> "/bot" <> token <> "/getChat?" <> URI.encode_query(%{chat_id: chat_id})
    request = Finch.build(:get, url)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true} = resp} -> {:reply, {:ok, resp}, state}
          _ -> {:reply, {:error, :bad_response}, state}
        end
      {:ok, %Finch.Response{status: s, body: b}} -> {:reply, {:error, {:status, s, b}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:edit_message_text, chat_id, message_id, text}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    url = base <> "/bot" <> token <> "/editMessageText"
    body = Jason.encode!(%{chat_id: chat_id, message_id: message_id, text: text, parse_mode: "HTML"})
    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true} = resp} -> {:reply, {:ok, resp}, state}
          _ -> {:reply, {:error, :bad_response}, state}
        end
      {:ok, %Finch.Response{status: s, body: b}} -> {:reply, {:error, {:status, s, b}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:pin_chat_message, chat_id, message_id}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    url = base <> "/bot" <> token <> "/pinChatMessage"
    body = Jason.encode!(%{chat_id: chat_id, message_id: message_id})
    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true} = resp} -> {:reply, {:ok, resp}, state}
          _ -> {:reply, {:error, :bad_response}, state}
        end
      {:ok, %Finch.Response{status: s, body: b}} -> {:reply, {:error, {:status, s, b}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unpin_chat_message, chat_id, message_id}, _from, state) do
    tg = Application.fetch_env!(:nostr2tg, :tg)
    base = Map.fetch!(tg, :api_base)
    token = Map.fetch!(tg, :bot_token)
    url = base <> "/bot" <> token <> "/unpinChatMessage"
    body = Jason.encode!(%{chat_id: chat_id, message_id: message_id})
    headers = [{"content-type", "application/json"}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true} = resp} -> {:reply, {:ok, resp}, state}
          _ -> {:reply, {:error, :bad_response}, state}
        end
      {:ok, %Finch.Response{status: s, body: b}} -> {:reply, {:error, {:status, s, b}}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
