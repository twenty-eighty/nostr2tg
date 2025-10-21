defmodule Nostr2tg.LinkBuilderTest do
  use ExUnit.Case

  alias Nostr2tg.LinkBuilder

  setup_all do
    relays = [
      "wss://relay.damus.io",
      "wss://nos.lol",
      "wss://relay.primal.net"
    ]

    Application.put_env(:nostr2tg, :nostr, %{relays: relays})
    {:ok, relays: relays}
  end

  test "encode nprofile produces TLV with pubkey and relays and decodes back", %{relays: relays} do
    pubkey_hex = "eb61c681c792331a253441d98f0346071011763836fa0de928b578c7cdb47a37"

    {:ok, nprofile} = :erlang.apply(LinkBuilder, :encode_nprofile, [pubkey_hex, %{}])
    require Logger
    Logger.debug("Built nprofile: #{nprofile}")

    assert String.starts_with?(nprofile, "nprofile1")

    {:ok, "nprofile", raw} = Bech32.decode(nprofile)

    <<0, 32, pubkey_bin::binary-size(32), rest::binary>> = raw
    assert Base.encode16(pubkey_bin, case: :lower) == String.downcase(pubkey_hex)

    # Relays are type 1 entries with ascii body; parse all TLVs
    parsed_relays =
      Stream.unfold(rest, fn
        <<>> ->
          nil

        bin when byte_size(bin) < 2 ->
          nil

        <<t, len, tail::binary>> ->
          if byte_size(tail) >= len do
            <<val::binary-size(len), rest2::binary>> = tail
            {{t, val}, rest2}
          else
            nil
          end
      end)
      |> Enum.filter(fn {t, _} -> t == 1 end)
      |> Enum.map(fn {_, v} -> v end)

    assert length(parsed_relays) >= 3
    assert MapSet.subset?(MapSet.new(relays), MapSet.new(parsed_relays))
  end

  test "encode naddr produces TLV with identifier, author and kind and decodes hrp" do
    event = %{
      "kind" => 30023,
      "pubkey" => "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
      "tags" => [["d", "post-123"]]
    }

    naddr = :erlang.apply(LinkBuilder, :encode_naddr, [event])
    assert String.starts_with?(naddr, "naddr1")

    {:ok, "naddr", _} = Bech32.decode(naddr)
  end

  test "nprofile matches nak encode when available", %{relays: relays} do
    require Logger

    case System.find_executable("nak") do
      nil ->
        Logger.debug("nak not available; skipping external encode check")
        assert true

      _ ->
        pubkey_hex = "eb61c681c792331a253441d98f0346071011763836fa0de928b578c7cdb47a37"
        {:ok, ours} = :erlang.apply(LinkBuilder, :encode_nprofile, [pubkey_hex, %{}, relays])

        nak_cmd =
          ["encode", "nprofile"] ++ Enum.flat_map(relays, fn r -> ["-r", r] end) ++ [pubkey_hex]

        {nak_out, status} = System.cmd("nak", nak_cmd, stderr_to_stdout: true)
        nak_np = String.trim(nak_out)
        Logger.debug("nak encode status=#{status} ours=#{ours} nak=#{nak_np}")
        assert status == 0, "nak failed to encode nprofile; status=#{status} output=#{nak_out}"
        assert ours == nak_np
    end
  end
end
