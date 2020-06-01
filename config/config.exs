use Mix.Config

config :ecto_arangodb,
  ecto_repos: [Test.Repo]

config :ecto_arangodb, Test.Repo,
  database: "friends_repo",
  endpoints: "http://192.168.1.138:8529"
