Logger.configure(level: :info)

Code.require_file("./support/test_repo.ex", __DIR__)
Code.require_file("./support/file_helpers.exs", __DIR__)

alias ArangoXEcto.Integration.{PoolRepo, TestRepo, DynamicRepo}

Application.put_env(:arangox_ecto, PoolRepo,
  pool_size: 10,
  max_restarts: 20,
  max_seconds: 10,
  log: false,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Application.put_env(:arangox_ecto, TestRepo,
  pool: ArangoXEcto.Sandbox,
  log: false,
  database: "arangox_ecto_test",
  endpoints: System.get_env("DB_ENDPOINT"),
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD")
)

Application.put_env(:arangox_ecto, DynamicRepo,
  pool: ArangoXEcto.Sandbox,
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
      use ExUnit.Case, unquote(Keyword.drop(opts, [:read, :write, :sandbox]))

      setup do
        :ok = ArangoXEcto.Sandbox.checkout(TestRepo, unquote(opts))
        :ok = ArangoXEcto.Sandbox.checkout(DynamicRepo, unquote(Keyword.drop(opts, [:write])))
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
{:ok, _pid} = PoolRepo.start_link()

:ok = ArangoXEcto.Migrator.up(TestRepo, 0, ArangoXEcto.Integration.Migration, log: false)
ArangoXEcto.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)

defmodule CompileTimeAssertions do
  defmodule DidNotRaise, do: defstruct(message: "")

  defmacro assert_compile_time_raise(expected_exception, expected_message, fun) do
    actual_exception =
      try do
        Code.eval_quoted(quote do: unquote(fun).())
        %DidNotRaise{}
      rescue
        e -> e
      end

    quote do
      assert unquote(actual_exception.__struct__) == unquote(expected_exception)
      assert unquote(actual_exception.message) =~ unquote(expected_message)
    end
  end
end

ExUnit.start(exclude: [:mix, :sandbox])
