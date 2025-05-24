defmodule TetoBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :teto_bot,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TetoBot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # api has breaking changes... wait for 0.11
      {:nostrum, github: "Kraigie/nostrum"},
      {:openai_ex, "~> 0.9.9"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"}
    ]
  end

  defp aliases do
    [
      # If defined, deploys assets and ecto using mix assets.deploy and mix ecto.deploy
      # https://railpack.com/languages/elixir/#_top
      "ecto.deploy": ["ecto.create", "ecto.migrate"]
    ]
  end
end
