use Mix.Config

config :arangox_ecto,
  ecto_repos: [Test.Repo]

config :arangox_ecto, Test.Repo,
  database: "friends_repo",
  endpoints: "http://192.168.1.138:8529"
