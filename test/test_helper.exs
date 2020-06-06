ExUnit.start()

alias EctoArangodbTest.Repo

Application.put_env(
  :ecto,
  Repo,
  adapter: ArangoXEcto,
  database: "friends_repo"
)

{:ok, _pid} = Repo.start_link()
