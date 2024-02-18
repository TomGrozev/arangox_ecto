Code.require_file("./support/test_repo.ex", __DIR__)
Code.require_file("./support/file_helpers.exs", __DIR__)

ExUnit.start()

alias ArangoXEctoTest.{Repo, DynamicRepo}

Application.put_env(:arangox_ecto, Repo,
  adapter: ArangoXEcto,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Application.put_env(:arangox_ecto, DynamicRepo,
  adapter: ArangoXEcto,
  static: false,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Code.require_file("./support/schemas.exs", __DIR__)

{:ok, _} = ArangoXEcto.Adapter.ensure_all_started(Repo, :temporary)
{:ok, _} = ArangoXEcto.Adapter.ensure_all_started(DynamicRepo, :temporary)

case Repo.__adapter__().storage_up(Repo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, term} -> raise inspect(term)
end

case DynamicRepo.__adapter__().storage_up(DynamicRepo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, term} -> raise inspect(term)
end

{:ok, _pid} = Repo.start_link()
{:ok, _pid} = DynamicRepo.start_link()

Process.flag(:trap_exit, true)
