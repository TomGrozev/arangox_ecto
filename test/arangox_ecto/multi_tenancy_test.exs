defmodule ArangoXEctoTest.MultiTenancyTest do
  use ArangoXEcto.Integration.Case, write: ["users"], sandbox: false

  alias ArangoXEcto.Integration.User
  alias ArangoXEcto.Integration.TestRepo

  setup do
    TestRepo.delete_all(User)
    TestRepo.delete_all(User, prefix: "tenant1")

    :ok
  end

  describe "using prefix" do
    test "it can insert with prefix" do
      TestRepo.insert(%User{first_name: "John", last_name: "Smith"})
      TestRepo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      assert {:ok, {1, [%{"first_name" => "John"}]}} =
               raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, {1, [%{"first_name" => "Bob"}]}} =
               raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can update with prefix" do
      {:ok, user} =
        TestRepo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      # this works because the prefix is stored in the module
      user
      |> Ecto.Changeset.change(first_name: "Billy")
      |> TestRepo.update()

      assert {:ok, {0, []}} = raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, {1, [%{"first_name" => "Billy"}]}} =
               raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can delete with prefix" do
      TestRepo.insert(%User{first_name: "John", last_name: "Smith"})

      {:ok, %{id: id} = user} =
        TestRepo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      # this works because the prefix is stored in the module
      assert {:ok, %{id: ^id}} = TestRepo.delete(user)

      assert {:ok, {1, [%{"first_name" => "John"}]}} =
               raw_prefix_query("arangox_ecto_test", "FOR u IN users RETURN u")

      assert {:ok, {0, []}} =
               raw_prefix_query("tenant1_arangox_ecto_test", "FOR u IN users RETURN u")
    end

    test "it can query using a prefix" do
      TestRepo.insert(%User{first_name: "Bob", last_name: "Smith"}, prefix: "tenant1")

      assert [] = TestRepo.all(User)
      assert [%{first_name: "Bob", last_name: "Smith"}] = TestRepo.all(User, prefix: "tenant1")
    end
  end

  defp raw_prefix_query(db, query) do
    ArangoXEcto.aql_query(TestRepo, query, [], database: db)
  end
end
