defmodule ArangoXEctoTest.ViewTest do
  use ExUnit.Case
  @moduletag :supported

  import Ecto.Query

  alias ArangoXEcto.View
  alias ArangoXEctoTest.{ArangoRepo, Repo}
  alias ArangoXEctoTest.Integration.UsersView

  @test_collections [
    :user_search
  ]

  # Gets connection
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    [conn: conn]
  end

  # Deletes each test view before every test
  setup %{conn: conn} = context do
    for collection <- @test_collections do
      Arangox.delete(conn, "/_api/view/#{collection}")
    end

    context
  end

  describe "searching using a view" do
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
