defmodule Nostr2tg.Nip05 do
  @moduledoc false

  @spec verify(String.t(), String.t(), String.t()) :: boolean
  def verify(name, domain, pubkey_hex) when is_binary(name) and is_binary(domain) and is_binary(pubkey_hex) do
    url = "https://" <> domain <> "/.well-known/nostr.json?name=" <> URI.encode(name)
    case Finch.build(:get, url) |> Finch.request(Nostr2tg.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        with {:ok, %{"names" => names}} <- Jason.decode(body),
             pk when is_binary(pk) <- Map.get(names, name) do
          String.downcase(pk) == String.downcase(pubkey_hex)
        else
          _ -> false
        end
      _ -> false
    end
  end
end
