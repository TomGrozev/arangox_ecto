defmodule ArangoXEcto.MixProject do
  use Mix.Project

  @version "1.3.1"
  @source_url "https://github.com/TomGrozev/arangox_ecto"

  def project do
    [
      app: :arangox_ecto,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Hex
      description: "An ArangoDB adapter for Ecto supporting Ecto queries and graph queries.",
      package: package(),
      # Docs
      name: "ArangoX Ecto",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: [],
      env: [
        log_levels: [:info],
        log_colours: %{info: :green, debug: :normal},
        log_in_colour: System.get_env("MIX_ENV") == "dev"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      ecto_dep(),
      {:arangox, ">= 0.5.5"},
      {:velocy, "~> 0.1"},
      {:jason, "~> 1.2"},
      {:geo, "~> 3.0"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:credo, "~> 1.6.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.18.0", only: [:dev, :test], runtime: false},
      {:git_hooks, "~> 0.7.0", only: [:test, :dev], runtime: false}
    ]
  end

  defp ecto_dep do
    if path = System.get_env("ECTO_PATH") do
      {:ecto, path: path}
    else
      {:ecto, "~> 3.9"}
    end
  end

  defp package do
    [
      maintainers: ["Tom Grozev"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(.formatter.exs mix.exs README.md lib)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "images/logo.png",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      canonical: "http://hex.pm/arangox_ecto",
      source_url: @source_url
    ]
  end
end
