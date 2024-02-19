defmodule ArangoXEctoTest.MigrationTest do
  use ExUnit.Case, async: true

  use ArangoXEcto.Migration

  import ArangoXEcto.Support.FileHelpers

  alias ArangoXEcto.Migration.{Collection, Index}
  alias ArangoXEcto.TestRepo
  alias ArangoXEcto.Migration.{Runner, SchemaMigration}
  #
  # @test_collections [
  #   :something
  # ]
  #
  # @test_views [
  #   :user_search
  # ]

  setup meta do
    config = Application.get_env(:arangox_ecto, TestRepo, [])
    Application.put_env(:arangox_ecto, TestRepo, Keyword.merge(config, meta[:repo_config] || []))
    on_exit(fn -> Application.put_env(:arangox_ecto, TestRepo, config) end)
  end

  setup meta do
    direction = meta[:direction] || :forward
    log = %{level: false, log_migrations: false}
    args = {self(), TestRepo, TestRepo.config(), __MODULE__, direction, :up, log}
    {:ok, runner} = Runner.start_link(args)
    Runner.metadata(runner, meta)
    {:ok, runner: runner}
  end

  test "defines __migration__ function" do
    assert function_exported?(__MODULE__, :__migration__, 0)
  end

  test "allows direction to be retrieved" do
    assert direction() == :up
  end

  test "allows repo to be retrieved" do
    assert repo() == TestRepo
  end

  @tag prefix: "foo"
  test "allows prefix to be retrieved" do
    assert prefix() == "foo"
  end

  test "creates a collection" do
    assert collection(:users) == %Collection{name: "users", type: 2}
    assert collection("users") == %Collection{name: "users", type: 2}
    assert collection(:users, type: :edge) == %Collection{name: "users", type: 3}

    assert collection(:users, prefix: "foo") == %Collection{
             name: "users",
             type: 2,
             prefix: "foo"
           }
  end

  test "creates an index" do
    assert index(:users, [:first_name]) ==
             %Index{
               collection_name: "users",
               unique: nil,
               name: "idx_users_first_name",
               fields: [:first_name]
             }

    assert index("users", [:first_name]) ==
             %Index{
               collection_name: "users",
               unique: nil,
               name: "idx_users_first_name",
               fields: [:first_name]
             }

    assert index(:users, :first_name, prefix: "foo") ==
             %Index{
               collection_name: "users",
               unique: nil,
               prefix: "foo",
               name: "idx_users_first_name",
               fields: [:first_name]
             }

    assert index(:users, [:first_name], name: :foo, unique: true) ==
             %Index{collection_name: "users", unique: true, name: :foo, fields: [:first_name]}

    assert index(:users, [:first_name], name: :foo, unique: true) ==
             %Index{collection_name: "users", unique: true, name: :foo, fields: [:first_name]}

    assert unique_index(:users, [:first_name], name: :foo) ==
             %Index{collection_name: "users", unique: true, name: :foo, fields: [:first_name]}

    assert unique_index(:users, :first_name, name: :foo) ==
             %Index{collection_name: "users", unique: true, name: :foo, fields: [:first_name]}

    assert unique_index(:collection_one__collection_two, :first_name) ==
             %Index{
               collection_name: "collection_one__collection_two",
               unique: true,
               name: "idx_collection_one__collection_two_first_name",
               fields: [:first_name]
             }
  end

  test ":migration_cast_version_field option" do
    {_repo, query, _options} =
      SchemaMigration.versions(TestRepo, [migration_cast_version_field: true], "")

    assert Macro.to_string(query.select.expr) == "type(&0.version(), :integer)"

    {_repo, query, _options} =
      SchemaMigration.versions(TestRepo, [migration_cast_version_field: false], "")

    assert Macro.to_string(query.select.expr) == "&0.version()"
  end

  test "runs a reversible command" do
    assert execute("RETURN 1", "RETURN 2") == :ok
  end

  test "chokes on alias types" do
    assert_raise ArgumentError, ~r"invalid migration type: Ecto.DateTime", fn ->
      add(:hello, Ecto.DateTime)
    end
  end

  test "flush clears out commands", %{runner: runner} do
    execute "TEST"
    commands = Agent.get(runner, & &1.commands)
    assert commands == ["TEST"]
    flush()
    commands = Agent.get(runner, & &1.commands)
    assert commands == []
  end

  describe "forward" do
    @describetag direction: :forward

    test "executes the given AQL" do
      execute "YOU'VE BEEN PUGGED!"
      flush()
      assert last_command() == "YOU'VE BEEN PUGGED!"
    end

    #
    # test "executes given keyword command" do
    #   execute create: "users", capped: true, size: 1024
    #   flush()
    #   assert last_command() == [create: "users", capped: true, size: 1024]
    # end

    test "creates a collection" do
      result =
        create(collection = collection(:users)) do
          add :first_name, :string
          add :money, :decimal, minimum: 0, comment: "Money the user has"
          add :likes, :integer, multiple_of: 10
          add :friends, {:array, :string}, min_items: 3
          add :active, :boolean
          add :type, :enum, values: ["user", :admin]
          add :provider, :const, value: "arangox_ecto"

          timestamps()
        end

      flush()

      assert last_command() ==
               {:create, collection,
                [
                  {:add, :first_name, :string, []},
                  {:add, :money, :decimal, [minimum: 0, comment: "Money the user has"]},
                  {:add, :likes, :integer, [multiple_of: 10]},
                  {:add, :friends, {:array, :string}, [min_items: 3]},
                  {:add, :active, :boolean, []},
                  {:add, :type, :enum, [values: ["user", :admin]]},
                  {:add, :provider, :const, [value: "arangox_ecto"]},
                  {:add, :inserted_at, :naive_datetime, []},
                  {:add, :updated_at, :naive_datetime, []}
                ]}

      assert result == collection(:users)
    end

    @tag repo_config: [migration_timestamps: [type: :utc_datetime]]
    test "create a collection with timestamps" do
      create(collection = collection(:users)) do
        timestamps()
      end

      flush()

      assert last_command() ==
               {:create, collection,
                [
                  {:add, :inserted_at, :utc_datetime, []},
                  {:add, :updated_at, :utc_datetime, []}
                ]}
    end

    test "creates a collection without updated_at timestamp" do
      create collection = collection(:users) do
        timestamps(inserted_at: :created_at, updated_at: false)
      end

      flush()

      assert last_command() ==
               {:create, collection, [{:add, :created_at, :naive_datetime, []}]}
    end

    test "creates a collection with timestamps of type date" do
      create collection = collection(:users) do
        timestamps(inserted_at: :inserted_on, updated_at: :updated_on, type: :date)
      end

      flush()

      assert last_command() ==
               {:create, collection,
                [
                  {:add, :inserted_on, :date, []},
                  {:add, :updated_on, :date, []}
                ]}
    end

    test "creates a collection without schema" do
      create collection = collection(:users)
      flush()

      assert last_command() ==
               {:create, collection, []}
    end

    test "alters a collection" do
      alter collection(:users) do
        add :summary, :string
        add_if_not_exists :summary, :string
        modify :friends, :integer
        remove :money
        remove :active, :boolean
        remove_if_exists :active, :boolean
      end

      flush()

      assert last_command() ==
               {:alter, %Collection{name: "users"},
                [
                  {:add, :summary, :string, []},
                  {:add_if_not_exists, :summary, :string, []},
                  {:modify, :friends, :integer, []},
                  {:remove, :money},
                  {:remove, :active, :boolean, []},
                  {:remove_if_exists, :active, :boolean, []}
                ]}
    end

    test "field modifications invoke type validations" do
      assert_raise ArgumentError, ~r"invalid migration type: Ecto.DateTime", fn ->
        alter collection(:users) do
          modify(:hello, Ecto.DateTime)
        end

        flush()
      end
    end

    test "rename field" do
      alter collection("users") do
        rename(:given_name, to: :first_name)
      end

      flush()

      assert last_command() ==
               {:alter, %Collection{name: "users"}, [{:rename, :given_name, :first_name}]}
    end

    test "drops a collection" do
      result = drop collection(:users)
      flush()
      assert {:drop, %Collection{}} = last_command()
      assert result == collection(:users)
    end

    test "drops a collection if collection exists" do
      result = drop_if_exists collection(:users)
      flush()
      assert {:drop_if_exists, %Collection{}} = last_command()
      assert result == collection(:users)
    end

    test "creates an index" do
      create index(:users, [:first_name])
      flush()
      assert {:create, %Index{}} = last_command()
    end

    test "drops an index" do
      drop index(:users, [:first_name])
      flush()
      assert {:drop, %Index{}} = last_command()
    end

    test "renames a collection" do
      result = rename(collection(:users), to: collection(:new_users))
      flush()

      assert {:rename, %Collection{name: "users"}, %Collection{name: "new_users"}} =
               last_command()

      assert result == collection(:new_users)
    end

    # prefix

    test "creates a collection with prefix from migration" do
      create(collection(:users, prefix: "foo"))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "foo"
    end

    @tag prefix: "foo"
    test "creates a collection with prefix from manager" do
      create(collection(:users))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "foo"
    end

    @tag prefix: "foo", repo_config: [migration_default_prefix: "baz"]
    test "creates a collection with prefix from manager overriding the default prefix configuration" do
      create(collection(:users))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "foo"
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "creates a collection with prefix from migration overriding the default prefix configuration" do
      create(collection(:users, prefix: "foo"))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "foo"
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "create a collection with prefix from configuration" do
      create(collection(:users))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "baz"
    end

    @tag prefix: :foo
    test "creates a collection with prefix from manager matching atom prefix" do
      create(collection(:users, prefix: "foo"))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == "foo"
    end

    @tag prefix: "foo"
    test "creates a collection with prefix from manager matching string prefix" do
      create(collection(:users, prefix: :foo))
      flush()

      {_, collection, _} = last_command()
      assert collection.prefix == :foo
    end

    @tag prefix: "bar"
    test "raise error when prefixes don't match" do
      assert_raise Ecto.MigrationError,
                   "the :prefix option `foo` does not match the migrator prefix `bar`",
                   fn ->
                     create(collection(:users, prefix: "foo"))
                     flush()
                   end
    end

    test "drops a collection with prefix from migration" do
      drop(collection(:users, prefix: "foo"))
      flush()
      {:drop, collection} = last_command()
      assert collection.prefix == "foo"
    end

    @tag prefix: "foo"
    test "drops a collection with prefix from manager" do
      drop(collection(:users))
      flush()
      {:drop, collection} = last_command()
      assert collection.prefix == "foo"
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "drops a collection with prefix from configuration" do
      drop(collection(:users))
      flush()
      {:drop, collection} = last_command()
      assert collection.prefix == "baz"
    end

    test "rename field on collection with index prefixed from migration" do
      alter collection(:users, prefix: "foo") do
        rename :given_name, to: :first_name
      end

      flush()

      {:alter, collection, [{:rename, _, new_name}]} = last_command()
      assert collection.prefix == "foo"
      assert new_name == :first_name
    end

    @tag prefix: "foo"
    test "rename field on collection with index prefixed from manager" do
      alter collection(:users, prefix: "foo") do
        rename :given_name, to: :first_name
      end

      flush()

      {:alter, collection, [{:rename, _, new_name}]} = last_command()
      assert collection.prefix == "foo"
      assert new_name == :first_name
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "rename field on collection with index prefixed from configuration" do
      alter collection(:users) do
        rename :given_name, to: :first_name
      end

      flush()

      {:alter, collection, [{:rename, _, new_name}]} = last_command()
      assert collection.prefix == "baz"
      assert new_name == :first_name
    end

    test "creates an index with prefix from migration" do
      create index(:users, [:first_name], prefix: "foo")
      flush()
      {_, index} = last_command()
      assert index.prefix == "foo"
    end

    @tag prefix: "foo"
    test "creates an index with prefix from manager" do
      create index(:users, [:first_name])
      flush()
      {_, index} = last_command()
      assert index.prefix == "foo"
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "creates an index with prefix from configuration" do
      create index(:users, [:first_name])
      flush()
      {_, index} = last_command()
      assert index.prefix == "baz"
    end

    test "drops an index with a prefix from migration" do
      drop index(:users, [:first_name], prefix: "foo")
      flush()
      {_, index} = last_command()
      assert index.prefix == "foo"
    end

    @tag prefix: "foo"
    test "drops an index with a prefix from manager" do
      drop index(:users, [:first_name])
      flush()
      {_, index} = last_command()
      assert index.prefix == "foo"
    end

    @tag repo_config: [migration_default_prefix: "baz"]
    test "drops an index with a prefix from configuration" do
      drop index(:users, [:first_name])
      flush()
      {_, index} = last_command()
      assert index.prefix == "baz"
    end

    test "executes a command" do
      execute "RETURN 1", "RETURN 2"
      flush()
      assert "RETURN 1" = last_command()
    end
  end

  test "fails gracefully with nested create" do
    assert_raise Ecto.MigrationError, "cannot execute nested commands", fn ->
      create collection(:users) do
        create index(:users, [:foo])
      end

      flush()
    end

    assert_raise Ecto.MigrationError, "cannot execute nested commands", fn ->
      create collection(:users) do
        create collection(:foo) do
        end
      end

      flush()
    end
  end

  ## Reverse

  describe "backward" do
    @describetag direction: :backward

    test "fails when executing AQL" do
      assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
        execute "YOU'VE BEEN PUGGED!"
        flush()
      end
    end

    test "creates a collection" do
      create collection = collection(:users) do
        add :first_name, :string
        add :money, :decimal, min: 0
      end

      flush()

      assert last_command() == {:drop, collection}
    end

    test "creates a collection if not exists" do
      create_if_not_exists collection = collection(:users) do
        add :first_name, :string
        add :money, :decimal, min: 0
      end

      flush()

      assert last_command() == {:drop_if_exists, collection}
    end

    test "creates an empty collection" do
      create collection = collection(:users)
      flush()

      assert last_command() == {:drop, collection}
    end

    test "alters a collection" do
      alter collection(:users) do
        add :summary, :string
        modify :people, :integer, from: :string
        modify :met, :string, from: :boolean
        modify :total, :string, min_length: 10, from: {:integer, max: 99}
      end

      flush()

      assert last_command() ==
               {:alter, %Collection{name: "users"},
                [
                  {:modify, :total, :integer, [from: {:string, min_length: 10}, max: 99]},
                  {:modify, :met, :boolean, [from: :string]},
                  {:modify, :people, :string, [from: :integer]},
                  {:remove, :summary, :string, []}
                ]}

      assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
        alter collection(:users) do
          add :summary, :string
          modify :summary, :integer
        end

        flush()
      end

      assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
        alter collection(:users) do
          add :summary, :string
          remove :summary
        end

        flush()
      end
    end

    test "removing a field (remove/3 called)" do
      alter collection(:users) do
        remove :first_name, :string, []
      end

      flush()

      assert {:alter, %Collection{name: "users"}, [{:add, :first_name, :string, []}]} =
               last_command()
    end

    test "removing a field (remove/2 called)" do
      alter collection(:users) do
        remove :first_name, :string
      end

      flush()

      assert {:alter, %Collection{name: "users"}, [{:add, :first_name, :string, []}]} =
               last_command()
    end

    test "rename field" do
      alter collection(:users) do
        rename :given_name, to: :first_name
      end

      flush()

      assert last_command() ==
               {:alter, %Collection{name: "users"}, [{:rename, :first_name, :given_name}]}
    end

    test "drops a collection" do
      assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
        drop collection(:users)
        flush()
      end
    end

    test "creates an index" do
      create index(:users, [:first_name])
      flush()
      assert {:drop, %Index{}} = last_command()
    end

    test "creates an index if not exists" do
      create_if_not_exists index(:users, [:title])
      flush()
      assert {:drop_if_exists, %Index{}} = last_command()
    end

    test "drops an index" do
      drop index(:users, [:first_name])
      flush()
      assert {:create, %Index{}} = last_command()
    end

    test "renames a collection" do
      rename collection(:users), to: collection(:new_users)
      flush()

      assert {:rename, %Collection{name: "new_users"}, %Collection{name: "users"}} =
               last_command()
    end

    test "reverses a command" do
      execute "RETURN 1", "RETURN 2"
      flush()
      assert "RETURN 2" = last_command()
    end
  end

  # describe "collection/3" do
  #   test "creates a document collection" do
  #     correct = %Migration.Collection{name: "something", type: 2}
  #
  #     assert ^correct = Migration.collection("something", :document)
  #   end
  #
  #   test "creates a document collection by default" do
  #     correct = %Migration.Collection{name: "something", type: 2}
  #
  #     assert ^correct = Migration.collection("something")
  #   end
  #
  #   test "creates an edge collection" do
  #     correct = %Migration.Collection{name: "something", type: 3}
  #
  #     assert ^correct = Migration.collection("something", :edge)
  #   end
  #
  #   test "accepts collection options" do
  #     correct = %Migration.Collection{
  #       name: "something",
  #       type: 2,
  #       keyOptions: %{type: :uuid},
  #       waitForSync: true
  #     }
  #
  #     assert ^correct =
  #              Migration.collection("something", :document,
  #                keyOptions: %{type: :uuid},
  #                waitForSync: true
  #              )
  #   end
  # end
  #
  # describe "edge/2" do
  #   test "creates an edge collection" do
  #     correct = %Migration.Collection{name: "something", type: 3}
  #
  #     assert ^correct = Migration.edge("something")
  #   end
  #
  #   test "accepts collection options" do
  #     correct = %Migration.Collection{
  #       name: "something",
  #       type: 3,
  #       keyOptions: %{type: :uuid},
  #       waitForSync: true
  #     }
  #
  #     assert ^correct =
  #              Migration.collection("something", :edge,
  #                keyOptions: %{type: :uuid},
  #                waitForSync: true
  #              )
  #   end
  # end
  #
  # describe "index/3" do
  #   test "creates an index with atom field" do
  #     correct = %Migration.Index{collection_name: "something", fields: [:email]}
  #
  #     assert ^correct = Migration.index("something", [:email])
  #   end
  #
  #   test "creates an index with string field" do
  #     correct = %Migration.Index{collection_name: "something", fields: ["email"]}
  #
  #     assert ^correct = Migration.index("something", ["email"])
  #   end
  #
  #   test "creates an index with atom fields" do
  #     correct = %Migration.Index{collection_name: "something", fields: [:email, :username]}
  #
  #     assert ^correct = Migration.index("something", [:email, :username])
  #   end
  #
  #   test "creates an index with string fields" do
  #     correct = %Migration.Index{collection_name: "something", fields: ["email", "username"]}
  #
  #     assert ^correct = Migration.index("something", ["email", "username"])
  #   end
  #
  #   test "creates an index with atom and string fields" do
  #     correct = %Migration.Index{collection_name: "something", fields: [:email, "username"]}
  #
  #     assert ^correct = Migration.index("something", [:email, "username"])
  #   end
  #
  #   test "creates an index with options" do
  #     correct = %Migration.Index{collection_name: "something", fields: [:email], unique: true}
  #
  #     assert ^correct = Migration.index("something", [:email], unique: true)
  #   end
  # end
  #
  # describe "create/1" do
  #   test "creates a view", %{conn: conn} do
  #     assert :ok = Migration.create(UsersView, repo: conn)
  #     assert {:error, "409 - duplicate name"} = Migration.create(UsersView, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"type" => "arangosearch"}}} =
  #              get_view_info(conn, UsersView.__view__(:name))
  #   end
  #
  #   test "creates analyzers", %{conn: conn} do
  #     assert :ok = Migration.create(Analyzers, repo: conn)
  #
  #     names =
  #       Analyzers.__analyzers__()
  #       |> Enum.map(&Atom.to_string(&1.name))
  #
  #     assert MapSet.equal?(MapSet.new(names), MapSet.new(get_analyzers(conn)))
  #   end
  #
  #   test "creates a document collection", %{conn: conn} do
  #     collection = Migration.collection("something")
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"type" => 2}}} =
  #              get_collection_info(conn, "something")
  #   end
  #
  #   test "creates an edge collection", %{conn: conn} do
  #     collection = Migration.edge("something")
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"type" => 3}}} =
  #              get_collection_info(conn, "something")
  #   end
  #
  #   test "errors on create existing collection", %{conn: conn} do
  #     collection = Migration.collection("something")
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert {:error, "409 - duplicate name"} = Migration.create(collection, repo: conn)
  #   end
  #
  #   test "creates a document collection with uuid key", %{conn: conn} do
  #     collection = Migration.collection("something", :document, keyOptions: %{type: :uuid})
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"type" => 2, "keyOptions" => %{"type" => "uuid"}}}} =
  #              get_collection_info(conn, "something")
  #   end
  #
  #   test "creates a edge collection with waitForSync", %{conn: conn} do
  #     collection = Migration.collection("something", :edge, waitForSync: true)
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"type" => 3, "waitForSync" => true}}} =
  #              get_collection_info(conn, "something")
  #   end
  #
  #   test "creates an index", %{conn: conn} do
  #     collection = Migration.collection("something")
  #     index = Migration.index("something", [:email])
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #     assert :ok = Migration.create(index, repo: conn)
  #
  #     assert {:ok, %Arangox.Response{body: %{"indexes" => [_, %{"fields" => ["email"]}]}}} =
  #              get_index_info(conn, "something")
  #   end
  #
  #   test "creates a unique index", %{conn: conn} do
  #     collection = Migration.collection("something")
  #     index = Migration.index("something", [:email], unique: true)
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #     assert :ok = Migration.create(index, repo: conn)
  #
  #     assert {:ok,
  #             %Arangox.Response{
  #               body: %{"indexes" => [_, %{"fields" => ["email"], "unique" => true}]}
  #             }} = get_index_info(conn, "something")
  #   end
  #
  #   test "creates a geojson index", %{conn: conn} do
  #     collection = Migration.collection("something")
  #     index = Migration.index("something", [:email], type: :geo, geoJson: true)
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #     assert :ok = Migration.create(index, repo: conn)
  #
  #     assert {:ok,
  #             %Arangox.Response{
  #               body: %{
  #                 "indexes" => [_, %{"fields" => ["email"], "type" => "geo", "geoJson" => true}]
  #               }
  #             }} = get_index_info(conn, "something")
  #   end
  # end
  #
  # describe "drop/1" do
  #   test "error on drop non existant collection", %{conn: conn} do
  #     assert {:error, "404 - collection or view not found"} =
  #              Migration.drop(Migration.collection("something"), conn)
  #   end
  #
  #   test "drops a document collection", %{conn: conn} do
  #     collection = Migration.collection("something")
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert :ok = Migration.drop(collection, conn)
  #   end
  #
  #   test "drops an edge collection", %{conn: conn} do
  #     collection = Migration.edge("something")
  #
  #     assert :ok = Migration.create(collection, repo: conn)
  #
  #     assert :ok = Migration.drop(collection, conn)
  #   end
  # end
  #
  # defp get_view_info(conn, name),
  #   do: Arangox.get(conn, "/_api/view/#{name}/properties")
  #
  # defp get_collection_info(conn, name),
  #   do: Arangox.get(conn, "/_api/collection/#{name}/properties")
  #
  # defp get_index_info(conn, collection_name),
  #   do: Arangox.get(conn, "/_api/index?collection=#{collection_name}")
  #
  # defp get_analyzers(conn) do
  #   analyzer_res =
  #     case Arangox.get(conn, "/_api/analyzer") do
  #       {:ok, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
  #       {:error, _} -> []
  #     end
  #
  #   Enum.filter(analyzer_res, fn %{"name" => name} ->
  #     String.starts_with?(name, "arangox_ecto_test::")
  #   end)
  #   |> Enum.map(fn %{"name" => name} -> String.slice(name, 19..-1) end)
  # end

  defp last_command(), do: Process.get(:last_command)
end
