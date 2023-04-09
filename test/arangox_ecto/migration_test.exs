defmodule ArangoXEctoTest.MigrationTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEcto.Migration
  alias ArangoXEctoTest.{ArangoRepo, Repo}
  alias ArangoXEctoTest.Integration.UsersView

  @test_collections [
    :something
  ]

  @test_views [
    :user_search
  ]

  # Gets connection
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    [conn: conn]
  end

  # Deletes each test collection before every test
  setup %{conn: conn} = context do
    for collection <- @test_collections do
      Arangox.delete(conn, "/_api/collection/#{collection}")
    end

    for view <- @test_views do
      Arangox.delete(conn, "/_api/view/#{view}")
    end

    context
  end

  describe "mix helpers" do
    test "repo directory name" do
      assert Regex.match?(~r|/priv/repo$|, Mix.ArangoXEcto.path_to_priv_repo(Repo))
      assert Regex.match?(~r|/priv/arango_repo$|, Mix.ArangoXEcto.path_to_priv_repo(ArangoRepo))
    end
  end

  describe "collection/3" do
    test "creates a document collection" do
      correct = %Migration.Collection{name: "something", type: 2}

      assert ^correct = Migration.collection("something", :document)
    end

    test "creates a document collection by default" do
      correct = %Migration.Collection{name: "something", type: 2}

      assert ^correct = Migration.collection("something")
    end

    test "creates an edge collection" do
      correct = %Migration.Collection{name: "something", type: 3}

      assert ^correct = Migration.collection("something", :edge)
    end

    test "accepts collection options" do
      correct = %Migration.Collection{
        name: "something",
        type: 2,
        keyOptions: %{type: :uuid},
        waitForSync: true
      }

      assert ^correct =
               Migration.collection("something", :document,
                 keyOptions: %{type: :uuid},
                 waitForSync: true
               )
    end
  end

  describe "edge/2" do
    test "creates an edge collection" do
      correct = %Migration.Collection{name: "something", type: 3}

      assert ^correct = Migration.edge("something")
    end

    test "accepts collection options" do
      correct = %Migration.Collection{
        name: "something",
        type: 3,
        keyOptions: %{type: :uuid},
        waitForSync: true
      }

      assert ^correct =
               Migration.collection("something", :edge,
                 keyOptions: %{type: :uuid},
                 waitForSync: true
               )
    end
  end

  describe "index/3" do
    test "creates an index with atom field" do
      correct = %Migration.Index{collection_name: "something", fields: [:email]}

      assert ^correct = Migration.index("something", [:email])
    end

    test "creates an index with string field" do
      correct = %Migration.Index{collection_name: "something", fields: ["email"]}

      assert ^correct = Migration.index("something", ["email"])
    end

    test "creates an index with atom fields" do
      correct = %Migration.Index{collection_name: "something", fields: [:email, :username]}

      assert ^correct = Migration.index("something", [:email, :username])
    end

    test "creates an index with string fields" do
      correct = %Migration.Index{collection_name: "something", fields: ["email", "username"]}

      assert ^correct = Migration.index("something", ["email", "username"])
    end

    test "creates an index with atom and string fields" do
      correct = %Migration.Index{collection_name: "something", fields: [:email, "username"]}

      assert ^correct = Migration.index("something", [:email, "username"])
    end

    test "creates an index with options" do
      correct = %Migration.Index{collection_name: "something", fields: [:email], unique: true}

      assert ^correct = Migration.index("something", [:email], unique: true)
    end
  end

  describe "create/1" do
    test "creates a view", %{conn: conn} do
      assert :ok = Migration.create(UsersView, conn)
      assert {:error, "409 - duplicate name"} = Migration.create(UsersView, conn)

      assert {:ok, %Arangox.Response{body: %{"type" => "arangosearch"}}} =
               get_view_info(conn, UsersView.__view__(:name))
    end

    test "creates a document collection", %{conn: conn} do
      collection = Migration.collection("something")

      assert :ok = Migration.create(collection, conn)

      assert {:ok, %Arangox.Response{body: %{"type" => 2}}} =
               get_collection_info(conn, "something")
    end

    test "creates an edge collection", %{conn: conn} do
      collection = Migration.edge("something")

      assert :ok = Migration.create(collection, conn)

      assert {:ok, %Arangox.Response{body: %{"type" => 3}}} =
               get_collection_info(conn, "something")
    end

    test "errors on create existing collection", %{conn: conn} do
      collection = Migration.collection("something")

      assert :ok = Migration.create(collection, conn)

      assert {:error, "409 - duplicate name"} = Migration.create(collection, conn)
    end

    test "creates a document collection with uuid key", %{conn: conn} do
      collection = Migration.collection("something", :document, keyOptions: %{type: :uuid})

      assert :ok = Migration.create(collection, conn)

      assert {:ok, %Arangox.Response{body: %{"type" => 2, "keyOptions" => %{"type" => "uuid"}}}} =
               get_collection_info(conn, "something")
    end

    test "creates a edge collection with waitForSync", %{conn: conn} do
      collection = Migration.collection("something", :edge, waitForSync: true)

      assert :ok = Migration.create(collection, conn)

      assert {:ok, %Arangox.Response{body: %{"type" => 3, "waitForSync" => true}}} =
               get_collection_info(conn, "something")
    end

    test "creates an index", %{conn: conn} do
      collection = Migration.collection("something")
      index = Migration.index("something", [:email])

      assert :ok = Migration.create(collection, conn)
      assert :ok = Migration.create(index, conn)

      assert {:ok, %Arangox.Response{body: %{"indexes" => [_, %{"fields" => ["email"]}]}}} =
               get_index_info(conn, "something")
    end

    test "creates a unique index", %{conn: conn} do
      collection = Migration.collection("something")
      index = Migration.index("something", [:email], unique: true)

      assert :ok = Migration.create(collection, conn)
      assert :ok = Migration.create(index, conn)

      assert {:ok,
              %Arangox.Response{
                body: %{"indexes" => [_, %{"fields" => ["email"], "unique" => true}]}
              }} = get_index_info(conn, "something")
    end

    test "creates a geojson index", %{conn: conn} do
      collection = Migration.collection("something")
      index = Migration.index("something", [:email], type: :geo, geoJson: true)

      assert :ok = Migration.create(collection, conn)
      assert :ok = Migration.create(index, conn)

      assert {:ok,
              %Arangox.Response{
                body: %{
                  "indexes" => [_, %{"fields" => ["email"], "type" => "geo", "geoJson" => true}]
                }
              }} = get_index_info(conn, "something")
    end
  end

  describe "drop/1" do
    test "error on drop non existant collection", %{conn: conn} do
      assert {:error, "404 - collection or view not found"} =
               Migration.drop(Migration.collection("something"), conn)
    end

    test "drops a document collection", %{conn: conn} do
      collection = Migration.collection("something")

      assert :ok = Migration.create(collection, conn)

      assert :ok = Migration.drop(collection, conn)
    end

    test "drops an edge collection", %{conn: conn} do
      collection = Migration.edge("something")

      assert :ok = Migration.create(collection, conn)

      assert :ok = Migration.drop(collection, conn)
    end
  end

  defp get_view_info(conn, name),
    do: Arangox.get(conn, "/_api/view/#{name}/properties")

  defp get_collection_info(conn, name),
    do: Arangox.get(conn, "/_api/collection/#{name}/properties")

  defp get_index_info(conn, collection_name),
    do: Arangox.get(conn, "/_api/index?collection=#{collection_name}")
end
