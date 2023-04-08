defmodule ArangoXEctoTest.ViewTest do
  use ExUnit.Case
  @moduletag :supported

  import Ecto.Query

  alias ArangoXEcto.View
  alias ArangoXEctoTest.{ArangoRepo, Repo}
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
    test "can search using ecto query for a view" do
      assert [%{first_name: "John", last_name: "Smith"}] = Repo.all(UsersView)
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
