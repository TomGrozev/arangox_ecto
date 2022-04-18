defmodule ArangoXEctoTest.MigrationTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEcto.Migration
  alias ArangoXEctoTest.Repo

  @test_collections [
    users: 2,
    test_edge: 3
  ]

  # Gets connection
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    [conn: conn]
  end

  # Deletes each test collection before every test
  setup %{conn: conn} = context do
    for {collection, _} <- @test_collections do
      Arangox.delete(conn, "/_api/collection/#{collection}")
    end

    context
  end

  describe "collection/3" do
    test "creates a document collection" do
      correct = %Migration.Collection{name: "users", type: 2}

      assert ^correct = Migration.collection("users", :document)
    end

    test "creates a document collection by default" do
      correct = %Migration.Collection{name: "users", type: 2}

      assert ^correct = Migration.collection("users")
    end

    test "creates an edge collection" do
      correct = %Migration.Collection{name: "users", type: 3}

      assert ^correct = Migration.collection("users", :edge)
    end

    test "accepts collection options" do
      correct = %Migration.Collection{
        name: "users",
        type: 2,
        keyOptions: %{type: :uuid},
        waitForSync: true
      }

      assert ^correct =
               Migration.collection("users", :document,
                 keyOptions: %{type: :uuid},
                 waitForSync: true
               )
    end
  end

  describe "edge/2" do
    test "creates an edge collection" do
      correct = %Migration.Collection{name: "users", type: 3}

      assert ^correct = Migration.edge("users")
    end

    test "accepts collection options" do
      correct = %Migration.Collection{
        name: "users",
        type: 3,
        keyOptions: %{type: :uuid},
        waitForSync: true
      }

      assert ^correct =
               Migration.collection("users", :edge,
                 keyOptions: %{type: :uuid},
                 waitForSync: true
               )
    end
  end

  describe "index/3" do
    test "creates an index with atom field" do
      correct = %Migration.Index{collection_name: "users", fields: [:email]}

      assert ^correct = Migration.index("users", [:email])
    end

    test "creates an index with string field" do
      correct = %Migration.Index{collection_name: "users", fields: ["email"]}

      assert ^correct = Migration.index("users", ["email"])
    end

    test "creates an index with atom fields" do
      correct = %Migration.Index{collection_name: "users", fields: [:email, :username]}

      assert ^correct = Migration.index("users", [:email, :username])
    end

    test "creates an index with string fields" do
      correct = %Migration.Index{collection_name: "users", fields: ["email", "username"]}

      assert ^correct = Migration.index("users", ["email", "username"])
    end

    test "creates an index with atom and string fields" do
      correct = %Migration.Index{collection_name: "users", fields: [:email, "username"]}

      assert ^correct = Migration.index("users", [:email, "username"])
    end

    test "creates an index with options" do
      correct = %Migration.Index{collection_name: "users", fields: [:email], unique: true}

      assert ^correct = Migration.index("users", [:email], unique: true)
    end
  end

  describe "create/1" do
    test "creates a document collection", %{conn: conn} do
      collection = Migration.collection("users")

      assert :ok = Migration.create(collection)

      assert {:ok, %Arangox.Response{body: %{"type" => 2}}} = get_collection_info(conn, "users")
    end

    test "creates an edge collection", %{conn: conn} do
      collection = Migration.edge("users")

      assert :ok = Migration.create(collection)

      assert {:ok, %Arangox.Response{body: %{"type" => 3}}} = get_collection_info(conn, "users")
    end

    test "errors on create existing collection" do
      collection = Migration.collection("users")

      assert :ok = Migration.create(collection)

      assert {:error, "409 - duplicate name"} = Migration.create(collection)
    end

    test "creates a document collection with uuid key", %{conn: conn} do
      collection = Migration.collection("users", :document, keyOptions: %{type: :uuid})

      assert :ok = Migration.create(collection)

      assert {:ok, %Arangox.Response{body: %{"type" => 2, "keyOptions" => %{"type" => "uuid"}}}} =
               get_collection_info(conn, "users")
    end

    test "creates a edge collection with waitForSync", %{conn: conn} do
      collection = Migration.collection("users", :edge, waitForSync: true)

      assert :ok = Migration.create(collection)

      assert {:ok, %Arangox.Response{body: %{"type" => 3, "waitForSync" => true}}} =
               get_collection_info(conn, "users")
    end

    test "creates an index", %{conn: conn} do
      collection = Migration.collection("users")
      index = Migration.index("users", [:email])

      assert :ok = Migration.create(collection)
      assert :ok = Migration.create(index)

      assert {:ok, %Arangox.Response{body: %{"indexes" => [_, %{"fields" => ["email"]}]}}} =
               get_index_info(conn, "users")
    end

    test "creates a unique index", %{conn: conn} do
      collection = Migration.collection("users")
      index = Migration.index("users", [:email], unique: true)

      assert :ok = Migration.create(collection)
      assert :ok = Migration.create(index)

      assert {:ok,
              %Arangox.Response{
                body: %{"indexes" => [_, %{"fields" => ["email"], "unique" => true}]}
              }} = get_index_info(conn, "users")
    end

    test "creates a geojson index", %{conn: conn} do
      collection = Migration.collection("users")
      index = Migration.index("users", [:email], type: :geo, geoJson: true)

      assert :ok = Migration.create(collection)
      assert :ok = Migration.create(index)

      assert {:ok,
              %Arangox.Response{
                body: %{
                  "indexes" => [_, %{"fields" => ["email"], "type" => "geo", "geoJson" => true}]
                }
              }} = get_index_info(conn, "users")
    end
  end

  describe "drop/1" do
    test "error on drop non existant collection" do
      assert {:error, "404 - collection or view not found"} =
               Migration.drop(Migration.collection("users"))
    end

    test "drops a document collection" do
      collection = Migration.collection("users")

      assert :ok = Migration.create(collection)

      assert :ok = Migration.drop(collection)
    end

    test "drops an edge collection" do
      collection = Migration.edge("users")

      assert :ok = Migration.create(collection)

      assert :ok = Migration.drop(collection)
    end
  end

  defp get_collection_info(conn, name),
    do: Arangox.get(conn, "/_api/collection/#{name}/properties")

  defp get_index_info(conn, collection_name),
    do: Arangox.get(conn, "/_api/index?collection=#{collection_name}")
end