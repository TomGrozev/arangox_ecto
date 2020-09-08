Code.require_file("./support/test_repo.ex", __DIR__)

ExUnit.start()

alias ArangoXEctoTest.Repo

Application.put_env(:arangox_ecto, Repo,
  adapter: ArangoXEcto,
  database: "arangox_ecto_test",
  endpoints: "http://192.168.1.138:8529"
)

Code.require_file("./support/schemas.exs", __DIR__)

{:ok, _} = ArangoXEcto.ensure_all_started(Ecto.Integration.TestRepo, :temporary)

{:ok, _pid} = Repo.start_link()

Process.flag(:trap_exit, true)
