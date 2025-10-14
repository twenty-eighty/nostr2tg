defmodule Nostr2tg.Nostr do
  @moduledoc false

  alias Nostr.Client

  @spec list_article_events_by_authors(non_neg_integer(), [String.t()], [String.t()]) ::
          {:ok, [map()]} | {:error, term()}
  def list_article_events_by_authors(since_ts, authors, relays) when is_list(authors) do
    filter = %{kinds: [30023], since: since_ts, authors: authors}
    Client.fetch(relays, filter, paginate: true, paginate_early_stop_threshold: 50)
  end

  @spec authors_from_mode(map()) :: {:ok, [String.t()]} | {:error, term()}
  def authors_from_mode(%{mode: "authors", authors: list}) when is_list(list), do: {:ok, list}

  def authors_from_mode(%{mode: "followlist", followlist: pubkey} = cfg) when is_binary(pubkey) do
    relays = Map.fetch!(cfg, :relays)
    fetch_following(relays, pubkey)
  end

  def authors_from_mode(_), do: {:error, :invalid_mode}

  @spec fetch_following([String.t()], String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @spec fetch_following([String.t()], String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def fetch_following(relays, pubkey) do
    # Fetch latest kind 3 contact list for the user
    case Client.fetch(relays, %{kinds: [3], authors: [pubkey], limit: 10}, paginate: true) do
      {:ok, events} when is_list(events) ->
        latest =
          events
          |> Enum.filter(&(&1["kind"] == 3))
          |> Enum.max_by(&(&1["created_at"] || 0), fn -> nil end)

        case latest do
          %{"tags" => tags} ->
            following =
              tags
              |> Enum.filter(fn t -> match?(["p", _ | _], t) end)
              |> Enum.map(fn ["p", pk | _] -> pk end)
              |> Enum.uniq()

            {:ok, following}

          _ ->
            {:ok, []}
        end

      other -> other
    end
  end

  @spec fetch_profiles([String.t()], [String.t()]) :: {:ok, map()} | {:error, term()}
  @spec fetch_profiles([String.t()], [String.t()]) :: {:ok, map()} | {:error, term()}
  def fetch_profiles(pubkeys, relays) do
    case Client.fetch(relays, %{kinds: [0], authors: pubkeys}, paginate: true) do
      {:ok, events} ->
        profile_map =
          events
          |> Enum.group_by(& &1["pubkey"])
          |> Enum.into(%{}, fn {pk, evs} ->
            latest = Enum.max_by(evs, &(&1["created_at"] || 0))
            profile = decode_profile(latest)
            {pk, profile}
          end)

        {:ok, profile_map}

      other ->
        other
    end
  end

  defp decode_profile(%{"content" => content}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_profile(_), do: %{}
end
