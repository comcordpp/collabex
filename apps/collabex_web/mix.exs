defmodule CollabExWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :collabex_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CollabExWeb.Application, []}
    ]
  end

  defp deps do
    [
      {:collabex, in_umbrella: true},
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6"}
    ]
  end
end
