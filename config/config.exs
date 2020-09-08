use Mix.Config

config :arangox_ecto,
  ecto_repos: [ArangoXEctoTest.Repo]

config :arangox_ecto, ArangoXEctoTest.Repo,
  database: "arangox_ecto_test",
  endpoints: "http://192.168.1.138:8529"
