Code.require_file("./support/test_repo.ex", __DIR__)

ExUnit.start()

alias ArangoXEctoTest.Repo

Application.put_env(:arangox_ecto, Repo,
  adapter: ArangoXEcto,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT")
)

Code.require_file("./support/schemas.exs", __DIR__)

{:ok, _} = ArangoXEcto.Adapter.ensure_all_started(Repo, :temporary)

case Repo.__adapter__().storage_up(Repo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, term} -> raise inspect(term)
end

{:ok, _pid} = Repo.start_link()

Process.flag(:trap_exit, true)
