ExUnit.start()

alias EctoArangodbTest.Repo

Application.put_env(
  :ecto,
  Repo,
  adapter: Ecto.Adapters.ArangoDB,
  database: "friends_repo"
)

{:ok, _pid} = Repo.start_link()
