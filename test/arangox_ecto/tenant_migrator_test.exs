defmodule ArangoXEctoTest.TenantMigratorTest do
  use ExUnit.Case

  import ArangoXEcto.Migrator
  import ExUnit.CaptureLog

  alias ArangoXEcto.TestRepo
  alias ArangoXEcto.View.Link

  defmodule Migration do
    use ArangoXEcto.Migration

    def up do
      execute "up"
    end

    def down do
      execute "down"
    end
  end

  defmodule ChangeMigration do
    use ArangoXEcto.Migration

    def change do
      create collection(:users) do
        add :first_name, :string
      end

      create view(:user_search) do
        add_sort(:created_at, :desc)
        add_store([:email], :lz4)

        add_link("new_test", %Link{
          includeAllFields: true,
          fields: %{
            first_name: %Link{
              analyzers: [:text_en]
            }
          }
        })
      end

      create index(:users, [:title])

      create analyzer(:a, :identity, [:norm])
    end
  end

  setup do
    {:ok, _} = start_supervised({MigrationsAgent, [{1, nil}, {2, nil}, {3, nil}]})
    :ok
  end

  def put_test_adapter_config(config) do
    Application.put_env(:arangox_ecto, ArangoXEcto.TestAdapter, config)

    on_exit(fn ->
      Application.delete_env(:arangox_ecto, ArangoXEcto.TestAdapter)
    end)
  end

  describe "dynamic_repo option" do
    test "upwards and downwards migrations" do
      assert run(TestRepo, [{3, ChangeMigration}, {4, Migration}], :up,
               to: 4,
               log: false,
               dynamic_repo: :tenant_db
             ) == [4]

      assert run(TestRepo, [{2, ChangeMigration}, {3, Migration}], :down,
               all: true,
               log: false,
               dynamic_repo: :tenant_db
             ) == [3, 2]
    end

    test "down invokes the repository adapter with down commands" do
      assert down(TestRepo, 0, Migration, log: false, dynamic_repo: :tenant_db) == :already_down
      assert down(TestRepo, 2, Migration, log: false, dynamic_repo: :tenant_db) == :ok
    end

    test "up invokes the repository adapter with up commands" do
      assert up(TestRepo, 3, Migration, log: false, dynamic_repo: :tenant_db) == :already_up
      assert up(TestRepo, 4, Migration, log: false, dynamic_repo: :tenant_db) == :ok
    end

    test "migrations run inside a transaction if the adapter supports ddl transactions" do
      capture_log(fn ->
        put_test_adapter_config(supports_ddl_transaction?: true, test_process: self())
        up(TestRepo, 0, Migration, dynamic_repo: :tenant_db)
        assert_receive {:transaction, _, _}
      end)
    end
  end
end
