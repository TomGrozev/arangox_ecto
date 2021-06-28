defmodule ArangoXEctoTest.Integration.RepoTest do
  use ExUnit.Case

  import Ecto.Query

  alias ArangoXEctoTest.Repo
  alias ArangoXEctoTest.Integration.{Post, User, UserPosts}

  @test_collections [
    users: 2,
    test_edge: 3,
    posts: 2,
    post_user: 3,
    user_user: 3,
    magics: 2
  ]

  # Deletes existing collections and creates testing collections
  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    # Get all collection names
    res =
      case Arangox.get(conn, "/_api/collection") do
        {:ok, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
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

  test "if the repo is already started" do
    assert {:error, {:already_started, _}} = Repo.start_link()
  end

  describe "Repo.all/2" do
    test "fetches empty" do
      assert [] == Repo.all(User)
      assert [] == Repo.all(from(u in User))
    end

    test "fetch with in" do
      %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      assert [] = Repo.all(from(u in User, where: u.first_name in []))
      assert [] = Repo.all(from(u in User, where: u.first_name in ["a", "b", "3"]))

      assert [_] = Repo.all(from(u in User, where: u.first_name not in []))
      assert [_] = Repo.all(from(u in User, where: u.first_name in ["1", "John", "3"]))
    end

    test "fetch with select and ordering" do
      %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      %User{first_name: "Ben", last_name: "Owens"} |> Repo.insert!()

      assert ["Ben", "John"] =
               Repo.all(from(u in User, order_by: u.first_name, select: u.first_name))

      assert ["Owens", "Smith"] =
               Repo.all(from(u in User, order_by: u.first_name, select: u.last_name))

      assert [_] = Repo.all(from(u in User, where: u.last_name == "Smith", select: u.id))
    end

    test "fetch using collection name" do
      %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      assert [_] = Repo.all(from(u in "users", select: u.id))
    end
  end

  describe "Repo.insert/2 and Repo.insert!/2" do
    test "can insert" do
      user = %User{first_name: "John", last_name: "Smith"}

      assert {:ok, %User{}} = Repo.insert(user)
      assert %User{} = Repo.insert!(user)
    end

    test "cannot insert missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Repo.insert(User.changeset(%User{}, %{}))

      assert_raise Ecto.InvalidChangesetError, ~r/could not perform/, fn ->
        Repo.insert!(User.changeset(%User{}, %{}))
      end
    end
  end

  test "can insert and fetch with timestamps" do
    datetime = NaiveDateTime.utc_now()
    assert %User{} = Repo.insert!(%User{inserted_at: datetime})

    assert [%{inserted_at: datetime}] = Repo.all(User)
  end

  test "can provide primary key" do
    user = %User{id: "123456", first_name: "John", last_name: "Smith"}

    assert {:ok, %User{}} = Repo.insert(user)

    user = %User{id: "654321", first_name: "John", last_name: "Smith"}
    assert %User{} = Repo.insert!(user)
  end

  describe "Repo.update/2 and Repo.update!/2" do
    test "can update" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      user = User.changeset(user, %{last_name: "Snow"})
      assert {:ok, %User{}} = Repo.update(user)

      user = User.changeset(user, %{last_name: "Smith"})
      assert %User{} = Repo.update!(user)
    end

    test "no change" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      changeset = User.changeset(user, %{})
      assert {:ok, user} = Repo.update(changeset)

      changeset = User.changeset(user, %{})
      assert user = Repo.update!(changeset)
    end

    test "cannot update removing required fields" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      user = User.changeset(user, %{last_name: nil})
      assert {:error, %Ecto.Changeset{}} = Repo.update(user)

      user = User.changeset(user, %{last_name: nil})

      assert_raise Ecto.InvalidChangesetError, ~r/could not perform/, fn ->
        Repo.update!(user)
      end
    end
  end

  describe "Repo.delete/2 and Repo.delete!/2" do
    test "can delete" do
      user = %User{first_name: "John", last_name: "Smith"}

      deleted_meta =
        user.__meta__
        |> Map.put(:state, :deleted)

      to_delete = Repo.insert!(user)

      assert {:ok, %User{__meta__: ^deleted_meta}} = Repo.delete(to_delete)

      to_delete = Repo.insert!(user)
      assert %User{__meta__: ^deleted_meta} = Repo.delete!(to_delete)
    end

    test "cannot delete non existent record" do
      user = %User{id: "123", first_name: "John", last_name: "Smith"}

      assert_raise Ecto.StaleEntryError, ~r/attempted to .* a stale struct/, fn ->
        Repo.delete(user)
      end

      assert_raise Ecto.StaleEntryError, ~r/attempted to .* a stale struct/, fn ->
        Repo.delete!(user)
      end
    end

    test "cannot delete un-inserted record" do
      user = %User{first_name: "John", last_name: "Smith"}

      assert_raise Ecto.NoPrimaryKeyValueError, ~r/struct .* is missing primary key value/, fn ->
        Repo.delete(user)
      end

      assert_raise Ecto.NoPrimaryKeyValueError, ~r/struct .* is missing primary key value/, fn ->
        Repo.delete!(user)
      end
    end
  end

  describe "unqiue constraints" do
    test "unique constraint" do
      changeset =
        User.changeset(%User{id: "1234", first_name: "Bob", last_name: "Bobington"}, %{})

      {:ok, _} = Repo.insert(changeset)

      exception =
        assert_raise Ecto.ConstraintError,
                     ~r/constraint error when attempting to insert struct/,
                     fn ->
                       changeset
                       |> Repo.insert!()
                     end

      assert exception.message =~ "unique constraint violated"
      assert exception.message =~ "The changeset has not defined any constraint."
    end

    test "custom unique constraint" do
      changeset =
        User.changeset(%User{id: "1234", first_name: "Bob", last_name: "Bobington"}, %{})

      {:ok, _} = Repo.insert(changeset)

      exception =
        assert_raise Ecto.ConstraintError,
                     ~r/constraint error when attempting to insert struct/,
                     fn ->
                       changeset
                       |> Ecto.Changeset.unique_constraint(:id, name: :test_constraint)
                       |> Repo.insert!()
                     end

      assert exception.message =~ "test_constraint (unique_constraint)"
    end
  end
end
