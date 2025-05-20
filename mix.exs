defmodule TetoBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :teto_bot,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      {:axon, "~> 0.7.0"},
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.6"},
      {:kino, "~> 0.14.0"},
      {:exla, "~> 0.9.0"}
    ]
  end
end
