defmodule Nostr2tg.Nip05 do
  @moduledoc false

  @spec verify(String.t(), String.t(), String.t()) :: {:ok, true} | {:error, term()}
  def verify(name, domain, pubkey_hex) when is_binary(name) and is_binary(domain) and is_binary(pubkey_hex) do
    url = "https://" <> domain <> "/.well-known/nostr.json?name=" <> URI.encode(name)
    case Req.get(url: url) do
      {:ok, %{status: 200, body: body}} ->
        data = if is_map(body), do: body, else: (case Jason.decode(body) do
          {:ok, map} -> map
          {:error, reason} -> {:invalid, reason}
        end)

        case data do
          %{"names" => names} ->
            case Map.get(names, name) do
              pk when is_binary(pk) ->
                if String.downcase(pk) == String.downcase(pubkey_hex) do
                  {:ok, true}
                else
                  {:error, {:pubkey_mismatch, expected: pubkey_hex, got: pk}}
                end

              nil -> {:error, :name_not_found}
            end

          {:invalid, reason} -> {:error, {:invalid_json, reason}}
          _other -> {:error, :invalid_json_structure}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end
end
