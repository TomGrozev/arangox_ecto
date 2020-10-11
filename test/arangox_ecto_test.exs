defmodule ArangoXEctoTest do
  use ExUnit.Case
  @moduletag :supported

  #  doctest ArangoXEcto

  alias ArangoXEctoTest.Integration.{Post, User, UserPosts}
  alias ArangoXEctoTest.Repo

  @test_collections [:users]

  @doc """
  Deletes existing collections and creates testing collections
  """
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
    for collection <- @test_collections do
      Arangox.post(conn, "/_api/collection", %{name: collection, type: 2})
    end

    [conn: conn]
  end

  @doc """
  Empties each collection before every test
  """
  setup %{conn: conn} = context do
    for collection <- @test_collections do
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
      user = %User{first_name: fname, last_name: lname} |> Repo.insert!()
      collection_name = User.__schema__(:source)

      result =
        ArangoXEcto.aql_query(
          Repo,
          """
          FOR var in users
          FILTER var.first_name == @fname AND var.last_name == @lname
          RETURN var
          """,
          fname: fname,
          lname: lname
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

  defp id_from_user(%{id: id}), do: "users/" <> id
end
