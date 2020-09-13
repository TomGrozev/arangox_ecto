defmodule ArangoXEctoTest do
  use ExUnit.Case
  @moduletag :supported

  doctest ArangoXEcto

  alias ArangoXEctoTest.Integration.{User, Post, UserPosts}
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

  test "create edge with no fields or custom name" do
    user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
    user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

    from = id_from_user(user1)
    to = id_from_user(user2)

    edge = ArangoXEcto.create_edge(Repo, user1, user2)

    assert Kernel.match?(%ArangoXEcto.Edge{_from: ^from, _to: ^to}, edge)
  end

  test "create edge with no fields and a custom name" do
    user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
    user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

    from = id_from_user(user1)
    to = id_from_user(user2)

    edge = ArangoXEcto.create_edge(Repo, user1, user2, collection_name: "friends")

    assert Kernel.match?(%ArangoXEcto.Edge{_from: ^from, _to: ^to}, edge)
  end

  test "create edge with fields and a custom module" do
    user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
    user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

    from = id_from_user(user1)
    to = id_from_user(user2)

    edge = ArangoXEcto.create_edge(Repo, user1, user2, edge: UserPosts, fields: %{type: "wrote"})

    assert Kernel.match?(%UserPosts{_from: ^from, _to: ^to, type: "wrote"}, edge)
  end


  defp id_from_user(%{id: id}), do: "users/" <> id
end
