defmodule ArangoXEctoTest.ViewTest do
  use ExUnit.Case
  @moduletag :supported

  import Ecto.Query
  import ArangoXEcto.Query, only: [search: 2, search: 3]

  alias ArangoXEctoTest.Repo
  alias ArangoXEctoTest.Integration.{User, UsersView}

  @test_collections [
    :users
  ]

  @test_views [
    :user_search
  ]

  # Gets connection
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    # Empties all test collections
    for collection <- @test_collections do
      Arangox.put(conn, "/_api/collection/#{collection}/truncate")
    end

    # Adds some test values into the test collections
    %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
    %User{first_name: "Bob", last_name: "Smith"} |> Repo.insert!()

    [conn: conn]
  end

  # Deletes each test view before every test
  setup %{conn: conn} = context do
    for view <- @test_views do
      Arangox.delete(conn, "/_api/view/#{view}")
    end

    context
  end

  describe "searching using a view" do
    test "ecto query can load a view results" do
      assert [%{first_name: "John", last_name: "Smith"}, _] = Repo.all(UsersView)

      assert [%User{first_name: "John", last_name: "Smith"}, _] =
               Repo.all(UsersView) |> ArangoXEcto.load(User)
    end

    test "can search using ecto query" do
      query =
        from(UsersView)
        |> search(first_name: "John")
        |> search([uv], uv.last_name == "Smith")

      assert %{first_name: "John", last_name: "Smith"} = Repo.one(query)
    end

    test "can search using analyzer in ecto query" do
      query =
        from(UsersView)
        |> search([uv], fragment("ANALYZER(? == ?, \"identity\")", uv.first_name, "John"))

      assert %{first_name: "John", last_name: "Smith"} = Repo.one(query)

      # make sure non existent analyzer returns empty
      query =
        from(UsersView)
        |> search([uv], fragment("ANALYZER(? == ?, \"text_en\")", uv.first_name, "John"))

      assert [] = Repo.all(query)
    end

    test "sorting by relevance" do
      query =
        from(UsersView)
        |> search(last_name: "Smith")
        |> order_by([uv], fragment("BM25(?)", uv))
        |> select([uv], {uv.first_name, fragment("BM25(?)", uv)})

      assert [{"John", score}, {"Bob", score}] = Repo.all(query)
    end

    test "can search using aql for a view" do
      ArangoXEcto.aql_query(
        Repo,
        """
        FOR us IN @@view
          SEARCH ANALYZER(us.name == @name, "text_en")
          RETURN us
        """,
        "@view": UsersView.__view__(:name),
        name: "bob"
      )
      |> dbg()

      assert true
    end
  end
end
