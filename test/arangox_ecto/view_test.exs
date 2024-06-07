defmodule ArangoXEcto.ViewTest do
  use ArangoXEcto.Integration.Case, sandbox: false

  @moduletag :integration

  import Ecto.Query
  import ArangoXEcto.Query, only: [search: 2, search: 3]

  alias ArangoXEcto.Integration.{DynamicRepo, TestRepo}
  alias ArangoXEcto.Integration.{PostsView, User, UsersView}

  setup_all do
    :ok = ArangoXEcto.Sandbox.checkout(TestRepo, sandbox: false, write: ["users"])
    TestRepo.delete_all(User)
    %User{first_name: "John", last_name: "Smith", gender: :male} |> TestRepo.insert!()
    %User{first_name: "Jane", last_name: "Smith", gender: :female} |> TestRepo.insert!()
    :ok = ArangoXEcto.Sandbox.checkin(TestRepo)

    Process.sleep(100)

    on_exit(fn ->
      :ok = ArangoXEcto.Sandbox.checkout(TestRepo, sandbox: false, write: ["users"])
      TestRepo.delete_all(User)
      :ok = ArangoXEcto.Sandbox.checkin(TestRepo)
    end)
  end

  describe "searching using a view" do
    test "does not allow querying of non-existent view in static mode" do
      assert_raise RuntimeError, ~r/does not exist. Maybe a migration is missing/, fn ->
        TestRepo.all(PostsView)
      end

      :ok = ArangoXEcto.create_view(DynamicRepo, PostsView)

      assert [] = DynamicRepo.all(PostsView)
    end

    test "ecto query can load a view results" do
      assert [_, %{first_name: "John", last_name: "Smith"}] = TestRepo.all(UsersView)

      assert [_, %User{first_name: "John", last_name: "Smith"}] =
               TestRepo.all(UsersView) |> ArangoXEcto.load(User)
    end

    test "can search using ecto query" do
      query =
        from(UsersView)
        |> search(first_name: "John")
        |> search([uv], uv.gender == :male)

      assert %{first_name: "John", last_name: "Smith"} = TestRepo.one(query)

      query =
        UsersView
        |> search(first_name: "John")

      assert %{first_name: "John", last_name: "Smith"} = TestRepo.one(query)
    end

    test "cannot update or delete a view" do
      query =
        from(UsersView)
        |> search(first_name: "John")

      assert_raise ArgumentError,
                   ~r/queries containing views cannot be update or delete operations/,
                   fn ->
                     TestRepo.update_all(query |> update(set: [last_name: "McClean"]), [])
                   end

      assert_raise ArgumentError,
                   ~r/queries containing views cannot be update or delete operations/,
                   fn ->
                     TestRepo.delete_all(query, [])
                   end
    end

    test "can search using analyzer in ecto query" do
      query =
        from(UsersView)
        |> search([uv], fragment("ANALYZER(? == ?, \"identity\")", uv.first_name, "John"))
        |> select([uv], uv)

      assert %{first_name: "John", last_name: "Smith"} =
               TestRepo.one(query)

      # make sure non existent analyzer returns empty
      query =
        from(UsersView)
        |> search([uv], fragment("ANALYZER(? == ?, \"text_en\")", uv.first_name, "John"))

      assert [] = TestRepo.all(query)
    end

    test "sorting by relevance" do
      query =
        from(UsersView)
        |> search(last_name: "Smith")
        |> order_by([uv], fragment("BM25(?)", uv))
        |> select([uv], {uv.first_name, fragment("BM25(?)", uv)})

      assert [{"Jane", score}, {"John", score}] = TestRepo.all(query)
    end

    test "can search using aql for a view" do
      query = """
      FOR uv IN @@view
        SEARCH ANALYZER(uv.first_name == @first_name, "identity")
        RETURN uv
      """

      assert {:ok, {1, [%{"first_name" => "John"}]}} =
               ArangoXEcto.aql_query(TestRepo, query,
                 "@view": UsersView.__view__(:name),
                 first_name: "John"
               )
    end
  end
end
