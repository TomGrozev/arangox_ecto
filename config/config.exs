import Config

config :arangox_ecto,
  ecto_repos: [ArangoXEctoTest.Repo]

config :arangox_ecto, ArangoXEctoTest.Repo,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT")

if Mix.env() != :prod do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix format --check-formatted"},
          {:cmd, "mix clean"},
          {:cmd, "mix compile --warnings-as-errors"},
          {:cmd, "mix credo"},
          {:cmd, "mix doctor --summary"}
        ]
      ],
      pre_push: [
        verbose: false,
        tasks: [
          {:cmd, "mix test"}
        ]
      ]
    ]
end
