Code.require_file("./support/test_repo.ex", __DIR__)
Code.require_file("./support/file_helpers.exs", __DIR__)

alias ArangoXEcto.Integration.{TestRepo, DynamicRepo}

Application.put_env(:arangox_ecto, TestRepo,
  pool: ArangoXEcto.Sandbox,
  show_sensitive_data_on_connection_error: true,
  log: false,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Application.put_env(:arangox_ecto, DynamicRepo,
  pool: ArangoXEcto.Sandbox,
  show_sensitive_data_on_connection_error: true,
  log: false,
  static: false,
  database: "arangox_ecto_dynamic_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Code.require_file("./support/schemas.exs", __DIR__)
Code.require_file("./support/migration.exs", __DIR__)

defmodule ArangoXEcto.Integration.Case do
  defmacro __using__(opts \\ []) do
    quote do
      use ExUnit.Case, unquote(opts)

      setup do
        :ok = ArangoXEcto.Sandbox.checkout(TestRepo, unquote(opts))
      end
    end
  end
end

{:ok, _} = ArangoXEcto.Adapter.ensure_all_started(TestRepo.config(), :temporary)
{:ok, _} = ArangoXEcto.Adapter.ensure_all_started(DynamicRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_ = ArangoXEcto.Adapter.storage_down(TestRepo.config())

_ =
  ArangoXEcto.Adapter.storage_down(
    TestRepo.config()
    |> Keyword.put(:database, "tenant1_arangox_ecto_test")
  )

_ = ArangoXEcto.Adapter.storage_down(DynamicRepo.config())

:ok = ArangoXEcto.Adapter.storage_up(TestRepo.config())

_ =
  ArangoXEcto.Adapter.storage_up(
    TestRepo.config()
    |> Keyword.put(:database, "tenant1_arangox_ecto_test")
  )

:ok = ArangoXEcto.Adapter.storage_up(DynamicRepo.config())

{:ok, _pid} = TestRepo.start_link()
{:ok, _pid} = DynamicRepo.start_link()

:ok = ArangoXEcto.Migrator.up(TestRepo, 0, ArangoXEcto.Integration.Migration, log: false)
ArangoXEcto.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)

ExUnit.start()
