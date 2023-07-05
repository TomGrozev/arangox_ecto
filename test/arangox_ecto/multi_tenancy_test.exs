defmodule ArangoXEctoTest.MultiTenancyTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEctoTest.Integration.User
  alias ArangoXEctoTest.Repo

  @databases [
    "arangox_ecto_test",
    "tenant1_arangox_ecto_test"
  ]

  @test_collections [
    "users"
  ]

  setup_all do
    {:ok, conn} =
      Repo.config()
      |> Keyword.put(:database, "_system")
      |> Arangox.start_link()

    # Delete DBs
    for db <- @databases do
      Arangox.delete(conn, "/_api/database/#{db}")
    end

    # Create DBs
    for db <- @databases do
      Arangox.post(conn, "/_api/database", %{name: db})
    end

    [conn: conn]
  end

  # Empties each collection before every test
  setup context do
    for db <- @databases do
      {:ok, conn} =
        Repo.config()
        |> Keyword.put(:database, db)
        |> Arangox.start_link()

      for collection <- @test_collections do
        Arangox.delete(conn, "/_api/collection/#{collection}")
        Arangox.post(conn, "/_api/collection", %{name: collection})
      end
    end

    context
  end

  describe "using prefix" do
    test "it can insert with prefix" do
      Repo.insert(%User{first_name: "John", last_name: "Smith"})
      Repo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      assert {:ok, [%{"first_name" => "John"}]} =
               raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, [%{"first_name" => "Bob"}]} =
               raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can update with prefix" do
      {:ok, user} = Repo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      # this works because the prefix is stored in the module
      user
      |> Ecto.Changeset.change(first_name: "Billy")
      |> Repo.update()

      assert {:ok, []} = raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, [%{"first_name" => "Billy"}]} =
               raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can delete with prefix" do
      Repo.insert(%User{first_name: "John", last_name: "Smith"})

      {:ok, %{id: id} = user} =
        Repo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      # this works because the prefix is stored in the module
      assert {:ok, %{id: ^id}} = Repo.delete(user)

      assert {:ok, [%{"first_name" => "John"}]} =
               raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, []} = raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can query using a prefix" do
      Repo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      assert [] = Repo.all(User)
      assert [%{first_name: "Bob", last_name: "Smith"}] = Repo.all(User, prefix: "tenant1")
    end
  end

  defp raw_prefix_query(db, query) do
    {:ok, conn} =
      Repo.config()
      |> Keyword.put(:database, db)
      |> Arangox.start_link()

    Arangox.transaction(conn, fn c ->
      Arangox.cursor(c, query)
      |> Enum.reduce([], fn resp, acc ->
        acc ++ resp.body["result"]
      end)
    end)
  end
end
