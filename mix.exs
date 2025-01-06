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
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ],
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
      mod: {ArangoXEcto.Application, []},
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
      {:arangox, "~> 0.6.0"},
      {:velocy, "~> 0.1"},
      {:jason, "~> 1.2"},
      {:geo, "~> 3.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21.0", only: [:dev, :test], runtime: false},
      {:git_hooks, "~> 0.7.0", only: [:test, :dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp ecto_dep do
    if path = System.get_env("ECTO_PATH") do
      {:ecto, path: path}
    else
      {:ecto, "~> 3.11"}
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
      main: "ArangoXEcto",
      source_ref: "v#{@version}",
      logo: "images/logo.png",
      extra_section: "GUIDES",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: extras(),
      before_closing_head_tag: &before_closing_head_tag/1,
      groups_for_extras: groups_for_extras(),
      groups_for_docs: [
        group_for_function("Migration")
      ],
      groups_for_modules: [
        ArangoSearch: [
          ArangoXEcto.Analyzer,
          ArangoXEcto.View,
          ArangoXEcto.View.Link
        ],
        Geo: [
          ArangoXEcto.GeoData,
          ArangoXEcto.Types.GeoJSON
        ],
        Migration: [
          ArangoXEcto.Migration,
          ArangoXEcto.Migration.Analyzer,
          ArangoXEcto.Migration.Collection,
          ArangoXEcto.Migration.Command,
          ArangoXEcto.Migration.Index,
          ArangoXEcto.Migration.JsonSchema,
          ArangoXEcto.Migration.View,
          ArangoXEcto.Migrator,
          ArangoXEcto.Sandbox
        ],
        "Relation structs": [
          ArangoXEcto.Association.EdgeMany,
          ArangoXEcto.Association.Graph
        ]
      ],
      canonical: "http://hex.pm/arangox_ecto"
    ]
  end

  defp before_closing_head_tag(:html) do
  """
  <script>
    function mermaidLoaded() {
      mermaid.initialize({
        startOnLoad: false,
        theme: document.body.className.includes("dark") ? "dark" : "default"
      });
      let id = 0;
      for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
        const preEl = codeEl.parentElement;
        const graphDefinition = codeEl.textContent;
        const graphEl = document.createElement("div");
        const graphId = "mermaid-graph-" + id++;
        mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
          graphEl.innerHTML = svg;
          bindFunctions?.(graphEl);
          preEl.insertAdjacentElement("afterend", graphEl);
          preEl.remove();
        });
      }
    }
  </script>
  <script async src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js" onload="mermaidLoaded();"></script>
  """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp extras do
    [
      "CHANGELOG.md"
    ]
  end

  defp group_for_function(group), do: {String.to_atom(group), &(&1[:group] == group)}

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Cheatsheets: ~r/cheetsheets\/.?/,
      "How-To's": ~r/guides\/howtos\/.?/
    ]
  end
end
