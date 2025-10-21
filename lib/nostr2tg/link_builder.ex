defmodule Nostr2tg.LinkBuilder do
  @moduledoc false
  require Logger

  @spec build_article_link(map(), map()) :: String.t()
  def build_article_link(%{"kind" => 30023} = event, profile) do
    cfg = Application.fetch_env!(:nostr2tg, :link)
    nip05_base = Map.fetch!(cfg, :nip05_base)
    naddr_base = Map.fetch!(cfg, :naddr_base)

    case {nip05_of(profile), article_identifier(event)} do
      {{:ok, name, domain}, {:ok, identifier}} ->
        case verify_nip05(name, domain, event["pubkey"]) do
          {:ok, true} ->
            Logger.info("NIP-05 verified for #{name}@#{domain}; using nip05 link")

            link =
              nip05_base
              |> String.trim_trailing("/")
              |> Kernel.<>("/" <> name <> "@" <> domain <> "/" <> identifier)

            Logger.debug("Built link: #{link}")
            link

          {:error, reason} ->
            Logger.info(
              "NIP-05 NOT verified for #{name}@#{domain}: #{inspect(reason)}; falling back to naddr"
            )

            naddr = encode_naddr(event)
            link = naddr_base <> naddr
            Logger.debug("Built link: #{link}")
            link
        end

      {{:ok, name, domain}, :error} ->
        Logger.info(
          "No article identifier (tag d) found; falling back to naddr for #{name}@#{domain}"
        )

        naddr = encode_naddr(event)
        link = naddr_base <> naddr
        Logger.debug("Built link: #{link}")
        link

      {_nip05_err, _} ->
        invalid =
          case profile do
            %{"nip05" => nip} -> nip
            _ -> nil
          end

        author = event["pubkey"]
        npub = npub_from_hex(author)
        which = npub || author

        Logger.info(
          "No valid nip05 in profile #{inspect(invalid)} for author #{which}; falling back to naddr"
        )

        naddr = encode_naddr(event)
        link = naddr_base <> naddr
        Logger.debug("Built link: #{link}")
        link
    end
  end

  @spec build_author_ref(map(), String.t(), map()) :: {String.t(), String.t()}
  def build_author_ref(profile, pubkey_hex, event) when is_binary(pubkey_hex) and is_map(event) do
    cfg = Application.fetch_env!(:nostr2tg, :link)
    nip05_base = Map.fetch!(cfg, :nip05_base)
    nprofile_base = Map.fetch!(cfg, :nprofile_base)

    display =
      Map.get(profile, "display_name") || Map.get(profile, "name") || default_display(pubkey_hex)

    case nip05_of(profile) do
      {:ok, name, domain} ->
        case verify_nip05(name, domain, pubkey_hex) do
          {:ok, true} ->
            # Same base as article link without trailing identifier: nip05_base/<name@domain>/
            url = String.trim_trailing(nip05_base, "/") <> "/" <> name <> "@" <> domain
            {display, url}

          _ ->
            # Fallback: nprofile link
            case encode_nprofile(pubkey_hex, event, relays_from_config()) do
              {:ok, nprofile} ->
                {display, String.trim_trailing(nprofile_base, "/") <> "/" <> nprofile}

              {:error, _} ->
                npub = npub_from_hex(pubkey_hex) || pubkey_hex
                {display, String.trim_trailing(nprofile_base, "/") <> "/" <> npub}
            end
        end

      :error ->
        case encode_nprofile(pubkey_hex, event, relays_from_config()) do
          {:ok, nprofile} ->
            {display, String.trim_trailing(nprofile_base, "/") <> "/" <> nprofile}

          {:error, _} ->
            npub = npub_from_hex(pubkey_hex) || pubkey_hex
            {display, String.trim_trailing(nprofile_base, "/") <> "/" <> npub}
        end
    end
  end

  defp default_display(pubkey_hex) do
    npub_from_hex(pubkey_hex) || pubkey_hex
  end

  defp nip05_of(%{"nip05" => nip05}) when is_binary(nip05) do
    case String.split(nip05, "@", parts: 2) do
      [name, domain] -> {:ok, name, domain}
      _ -> :error
    end
  end

  defp nip05_of(_), do: :error

  defp article_identifier(%{"tags" => tags}) do
    case Enum.find(tags, fn
           ["d", _ | _] -> true
           _ -> false
         end) do
      ["d", ident | _] when is_binary(ident) -> {:ok, ident}
      _ -> :error
    end
  end

  defp verify_nip05(name, domain, pubkey_hex), do: Nostr2tg.Nip05.verify(name, domain, pubkey_hex)

  @spec encode_naddr(map()) :: String.t()
  def encode_naddr(%{"kind" => kind, "pubkey" => pubkey, "tags" => tags}) do
    # NIP-19 naddr TLV per spec:
    # 0 = identifier ("d" tag string)
    # 1 = relay (ascii, repeatable)
    # 2 = author (32-byte pubkey)
    # 3 = kind (32-bit unsigned, big-endian)
    identifier =
      case Enum.find(tags, fn t -> match?(["d", _], t) end) do
        ["d", ident] -> ident
        _ -> ""
      end

    kind_bin = <<kind::32-big>>

    author_bin =
      case decode_hex32(pubkey) do
        {:ok, bin} -> bin
        :error -> <<>>
      end

    id_bin = identifier

    relays =
      case Application.get_env(:nostr2tg, :nostr) do
        %{relays: list} when is_list(list) -> list
        _ -> []
      end

    relays_norm = Enum.map(relays, &String.trim_trailing(&1, "/"))

    Logger.debug(
      "naddr input: kind=#{inspect(kind)} pubkey_hex_len=#{String.length(to_string(pubkey))} author_bin_size=#{byte_size(author_bin)} identifier=#{inspect(identifier)} relays=#{inspect(relays_norm)}"
    )

    tlv =
      <<0, byte_size(id_bin), id_bin::binary>> <>
        (relays_norm
         |> Enum.map(fn r -> <<1, byte_size(r), r::binary>> end)
         |> IO.iodata_to_binary()) <>
        <<2, byte_size(author_bin), author_bin::binary>> <>
        <<3, byte_size(kind_bin), kind_bin::binary>>

    Logger.debug(
      "naddr tlv sizes: id_bin=#{byte_size(id_bin)} author_bin=#{byte_size(author_bin)} kind_bin=#{byte_size(kind_bin)} relays=#{length(relays_norm)} tlv_total=#{byte_size(tlv)}"
    )

    data5 = Bech32.convertbits(tlv, 8, 5, false)
    Bech32.encode_from_5bit("naddr", data5)
  end

  @spec encode_nprofile(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def encode_nprofile(pubkey_hex, event) when is_binary(pubkey_hex) and is_map(event) do
    encode_nprofile(pubkey_hex, event, relays_from_config())
  end

  @spec encode_nprofile(String.t(), map(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def encode_nprofile(pubkey_hex, _event, relays)
      when is_binary(pubkey_hex) and is_list(relays) do
    # NIP-19 nprofile TLV: 0 = 32-byte pubkey, 1 = relay (repeat). See NIP-19.
    case decode_hex32(pubkey_hex) do
      {:ok, author_bin} when byte_size(author_bin) == 32 ->
        relays_norm =
          relays
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim_trailing(&1, "/"))
          |> Enum.uniq()
          |> Enum.sort()

        if relays_norm == [] do
          {:error, :no_relays}
        else
          tlv =
            <<0, byte_size(author_bin), author_bin::binary>> <>
              (relays_norm
               |> Enum.map(fn r -> <<1, byte_size(r), r::binary>> end)
               |> IO.iodata_to_binary())

          data5 = Bech32.convertbits(tlv, 8, 5, false)
          {:ok, Bech32.encode_from_5bit("nprofile", data5)}
        end

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  defp relays_from_config do
    case Application.get_env(:nostr2tg, :nostr) do
      %{relays: list} when is_list(list) -> list
      _ -> []
    end
  end

  defp decode_hex32(hex) when is_binary(hex) do
    try do
      bin = Base.decode16!(hex, case: :mixed)
      if byte_size(bin) == 32, do: {:ok, bin}, else: :error
    rescue
      ArgumentError -> :error
    end
  end

  defp npub_from_hex(hex) when is_binary(hex) do
    case decode_hex32(hex) do
      {:ok, bin} ->
        data5 = Bech32.convertbits(bin, 8, 5, true)
        Bech32.encode_from_5bit("npub", data5)

      :error ->
        nil
    end
  end
end
