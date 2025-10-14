defmodule Nostr2tg.MixProject do
  use Mix.Project

  def project do
    [
      app: :nostr2tg,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Nostr2tg.Application, []}
    ]
  end

  defp dialyzer do
    [
      app_tree: true,
      plt_add_apps: [:mix],
      flags: [:unmatched_returns, :error_handling, :no_opaque],
      list_unused_filters: true
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostr_access, "~> 0.1.3"},
      {:finch, "~> 0.17"},
      {:castore, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:bech32, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
