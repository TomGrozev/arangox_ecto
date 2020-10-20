defmodule ArangoXEctoTest do
  use ExUnit.Case
  @moduletag :supported

  #  doctest ArangoXEcto

  alias ArangoXEctoTest.Integration.{Post, User, UserPosts}
  alias ArangoXEctoTest.Repo

  @test_collections [users: 2, test_edge: 3]

  # Deletes existing collections and creates testing collections
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    # Get all collection names
    res =
      case Arangox.get(conn, "/_api/collection") do
        {:ok, _, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
        {:error, _} -> []
      end

    collection_names =
      Enum.map(res, fn %{"name" => name} -> name end)
      |> Enum.filter(&(!String.starts_with?(&1, "_")))

    # Delete all collections
    for collection <- collection_names do
      Arangox.delete(conn, "/_api/collection/#{collection}")
    end

    # Create test collections
    for {collection, type} <- @test_collections do
      Arangox.post(conn, "/_api/collection", %{name: collection, type: type})
    end

    [conn: conn]
  end

  # Empties each collection before every test
  setup %{conn: conn} = context do
    for {collection, _type} <- @test_collections do
      Arangox.put(conn, "/_api/collection/#{collection}/truncate")
    end

    context
  end

  describe "aql_query/4" do
    test "invalid AQL query" do
      assert_raise Arangox.Error, ~r/\[400\] \[1501\] AQL: syntax error/i, fn ->
        ArangoXEcto.aql_query(
          Repo,
          """
          FOsdfsdfgdfs abc
          """
        )
      end
    end

    test "non existent collection AQL query" do
      assert_raise Arangox.Error, ~r/\[404\] \[1203\] AQL: collection or view not found/, fn ->
        ArangoXEcto.aql_query(
          Repo,
          """
          FOR var in non_existent
          RETURN var
          """
        )
      end
    end

    test "filter AQL query" do
      fname = "John"
      lname = "Smith"
      %User{first_name: fname, last_name: lname} |> Repo.insert!()

      collection_name = User.__schema__(:source)

      result =
        ArangoXEcto.aql_query(
          Repo,
          """
          FOR var in @@collection_name
          FILTER var.first_name == @fname AND var.last_name == @lname
          RETURN var
          """,
          [{:"@collection_name", collection_name}, fname: fname, lname: lname]
        )

      assert Kernel.match?(
               {:ok,
                [
                  %{
                    "_id" => _,
                    "_key" => _,
                    "_rev" => _,
                    "first_name" => ^fname,
                    "last_name" => ^lname
                  }
                ]},
               result
             )
    end
  end

  describe "create_edge/4" do
    test "create edge with no fields or custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(Repo, user1, user2)

      assert Kernel.match?(%{_from: ^from, _to: ^to}, edge)
    end

    test "create edge with no fields and a custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(Repo, user1, user2, collection_name: "friends")

      assert Kernel.match?(%{_from: ^from, _to: ^to}, edge)
    end

    test "create edge with fields and a custom module" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge =
        ArangoXEcto.create_edge(Repo, user1, user2, edge: UserPosts, fields: %{type: "wrote"})

      assert Kernel.match?(%UserPosts{_from: ^from, _to: ^to, type: "wrote"}, edge)
    end
  end

  describe "delete_all_edges/4" do
    # TODO Create Tests
  end

  describe "get_id_from_struct/1" do
    test "valid struct" do
      assert ArangoXEcto.get_id_from_struct(%User{id: "12345"}) == "users/12345"
    end

    test "invalid map" do
      assert_raise ArgumentError, ~r/Invalid struct or _id/, fn ->
        ArangoXEcto.get_id_from_struct(%{id: "1234"})
      end
    end

    test "does not allow random map" do
      assert_raise ArgumentError, ~r/Invalid struct or _id/, fn ->
        ArangoXEcto.get_id_from_struct(%{abc: "jnsdkjfsdfnkj"})
      end
    end

    test "valid id passed" do
      assert ArangoXEcto.get_id_from_struct("users/1235")
    end

    test "invalid id string" do
      assert_raise ArgumentError, ~r/Invalid format for ArangoDB document ID/, fn ->
        ArangoXEcto.get_id_from_struct("sdnkjsdkjf")
      end
    end
  end

  describe "raw_to_struct/2" do
    # TODO Create Tests
  end

  describe "edge_module/3" do
    test "two modules with same parents" do
      assert ArangoXEcto.edge_module(User, Post) == ArangoXEctoTest.Integration.Edges.UsersPosts
    end

    test "one module with extra depth in parent" do
      assert ArangoXEcto.edge_module(User, ArangoXEctoTest.Integration.Deep.Magic) ==
               ArangoXEctoTest.Integration.Edges.UsersMagics
    end

    test "using custom colleciton name" do
      assert ArangoXEcto.edge_module(User, Post, collection_name: "member_blogs") ==
               ArangoXEctoTest.Integration.Edges.MemberBlogs
    end
  end

  describe "collection_exists?/3" do
    test "collection does exist" do
      assert ArangoXEcto.collection_exists?(Repo, :users)
    end

    test "collection does not exist" do
      assert not ArangoXEcto.collection_exists?(Repo, :fake_collection)
    end

    test "string and atom collection names" do
      assert ArangoXEcto.collection_exists?(Repo, :users)
      assert ArangoXEcto.collection_exists?(Repo, "users")
    end

    test "edge collection exists" do
      assert ArangoXEcto.collection_exists?(Repo, :test_edge, :edge)
    end

    test "atom and integer types" do
      assert ArangoXEcto.collection_exists?(Repo, :users, :document)
      assert ArangoXEcto.collection_exists?(Repo, :users, 2)
    end
  end

  describe "is_edge?/1" do
    # TODO Create tests
  end

  describe "is_document?/1" do
    # TODO Create tests
  end

  describe "schema_type!/1" do
    # TODO Create tests
  end

  defp id_from_user(%{id: id}), do: "users/" <> id
end
