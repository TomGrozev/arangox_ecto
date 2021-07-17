defmodule ArangoXEctoTest.Integration.RepoTest do
  use ExUnit.Case

  import Ecto.Query

  alias ArangoXEctoTest.Repo
  alias ArangoXEctoTest.Integration.{Post, User}

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

    assert [%{inserted_at: ^datetime}] = Repo.all(User)
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
      assert Repo.update!(changeset) = user
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

  describe "Repo.get/3 and Repo.get!/3" do
    test "get items" do
      user = Repo.insert!(%User{first_name: "John", last_name: "Smith"})
      post = Repo.insert!(%Post{title: "My Blog"})

      assert user == Repo.get(User, user.id)
      # with casting
      assert post == Repo.get(Post, to_string(post.id))

      assert user == Repo.get!(User, user.id)
      # with casting
      assert post == Repo.get!(Post, to_string(post.id))
    end

    test "can't get non existent" do
      assert nil == Repo.get(User, "1")

      assert_raise Ecto.NoResultsError, fn ->
        Repo.get!(Post, "1")
      end
    end
  end

  describe "Repo.get_by/3 and Repo.get_by!/3" do
    test "get items" do
      user = Repo.insert!(%User{first_name: "John", last_name: "Smith"})
      post = Repo.insert!(%Post{title: "My Blog"})

      assert user == Repo.get_by(User, id: user.id)
      assert user == Repo.get_by(User, first_name: user.first_name)
      assert user == Repo.get_by(User, id: user.id, first_name: user.first_name)
      # with casting
      assert post == Repo.get_by(Post, id: to_string(post.id))

      assert user == Repo.get_by!(User, id: user.id)
      assert user == Repo.get_by!(User, first_name: user.first_name)
      assert user == Repo.get_by!(User, id: user.id, first_name: user.first_name)
      # with casting
      assert post == Repo.get_by!(Post, id: to_string(post.id))
    end

    test "can't find wrong values" do
      post = Repo.insert!(%Post{title: "My Blog"})

      assert nil == Repo.get_by(Post, title: "abc")
      assert nil == Repo.get_by(Post, id: post.id, title: "abc")

      assert_raise Ecto.NoResultsError, fn ->
        Repo.get_by!(Post, id: "1", title: "hello")
      end
    end
  end

  describe "first, last and one / one!" do
    test "first" do
      user1 = Repo.insert!(%User{first_name: "John", last_name: "Smith"})
      user2 = Repo.insert!(%User{first_name: "Ben", last_name: "Bark"})

      assert user1 == User |> first |> Repo.one()

      assert user2 == from(u in User, order_by: u.first_name) |> first |> Repo.one()

      assert user1 == from(u in User, order_by: [desc: u.first_name]) |> first |> Repo.one()

      query = from(u in User, where: is_nil(u.id))
      refute query |> first |> Repo.one()

      assert_raise Ecto.NoResultsError, fn ->
        query |> first |> Repo.one!()
      end
    end

    test "last" do
      user1 = Repo.insert!(%User{first_name: "John", last_name: "Smith"})
      user2 = Repo.insert!(%User{first_name: "Ben", last_name: "Bark"})

      assert user2 == User |> last |> Repo.one()

      assert user1 == from(u in User, order_by: u.first_name) |> last |> Repo.one()

      assert user2 == from(u in User, order_by: [desc: u.first_name]) |> last |> Repo.one()

      query = from(u in User, where: is_nil(u.id))
      refute query |> last |> Repo.one()

      assert_raise Ecto.NoResultsError, fn ->
        query |> last |> Repo.one!()
      end
    end
  end

  describe "insert_all/3" do
    test "regular insert_all" do
      assert {2, nil} = Repo.insert_all(Post, [[title: "abc"], %{title: "cba"}])
      assert {2, nil} = Repo.insert_all({"posts", Post}, [[title: "def"], %{title: "fed"}])

      assert [%Post{title: "abc"}, %Post{title: "cba"}, %Post{title: "def"}, %Post{title: "fed"}] =
               Repo.all(Post |> order_by(:title))

      # Does not allow string collection name
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        Repo.insert_all("posts", [[title: "abc"], %{title: "cba"}])
      end
    end

    test "insert_all with no fields" do
      assert {2, nil} = Repo.insert_all(Post, [[], []])
      assert [%Post{}, %Post{}] = Repo.all(Post)
    end

    test "insert_all no objects" do
      assert {0, nil} = Repo.insert_all("posts", [])
      assert {0, nil} = Repo.insert_all({"posts", Post}, [])
    end

    @tag :returning
    test "insert_all with returning schema" do
      assert {0, []} = Repo.insert_all(Post, [], returning: true)
      assert {0, nil} = Repo.insert_all(Post, [], returning: false)
    end

    @tag :returning
    test "insert_all with returning some fields" do
      {2, [p1, p2]} =
        Repo.insert_all(Post, [[title: "abc"], [title: "cba"]], returning: [:id, :title])

      assert %Post{title: "abc", __meta__: %{state: :loaded}} = p1
      assert %Post{title: "cba", __meta__: %{state: :loaded}} = p2
    end

    @tag :returning
    test "insert_all with returning all fields" do
      {2, [p1, p2]} = Repo.insert_all(Post, [[title: "abc"], [title: "cba"]], returning: true)

      assert %Post{title: "abc", __meta__: %{state: :loaded}} = p1
      assert %Post{title: "cba", __meta__: %{state: :loaded}} = p2
    end

    test "insert_all with dumping" do
      datetime = ~N[2021-01-01 01:20:30.000000]
      assert {2, nil} = Repo.insert_all(Post, [%{inserted_at: datetime}, %{title: "abc"}])

      assert [%Post{inserted_at: ^datetime, title: nil}, %Post{inserted_at: nil, title: "abc"}] =
               Repo.all(Post |> order_by(:title))
    end
  end

  describe "update_all/3" do
    test "regular updates" do
      assert %Post{id: id1} = Repo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = Repo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = Repo.insert!(%Post{title: "ghi"})

      assert {0, []} =
               Repo.update_all(
                 from(p in Post, where: false, select: [:id]),
                 set: [title: "123"]
               )

      assert {3, []} = Repo.update_all(Post, set: [title: "123"])

      assert %Post{title: "123"} = Repo.get(Post, id1)
      assert %Post{title: "123"} = Repo.get(Post, id2)
      assert %Post{title: "123"} = Repo.get(Post, id3)
    end

    # `:returning` attribute no longer is included in query evaluation
    # I am unlikely to implement this features as it would require a rework of some code. PRs are welcome.
    # @tag :returning
    # test "update_all with returning" do
    #  assert %Post{id: id1} = Repo.insert!(%Post{title: "abc"})
    #  assert %Post{id: id2} = Repo.insert!(%Post{title: "def"})
    #  assert %Post{id: id3} = Repo.insert!(%Post{title: "ghi"})

    #  assert {3, posts} = Repo.update_all(Post, [set: [title: "123"]], returning: true)

    #  [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    #  assert %Post{id: ^id1, title: "123"} = p1
    #  assert %Post{id: ^id2, title: "123"} = p2
    #  assert %Post{id: ^id3, title: "123"} = p3

    #  assert {3, posts} = Repo.update_all(Post, [set: [text: "hello"]], returning: [:id, :text])

    #  [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    #  assert %Post{id: ^id1, title: nil, text: "hello"} = p1
    #  assert %Post{id: ^id2, title: nil, text: "hello"} = p2
    #  assert %Post{id: ^id3, title: nil, text: "hello"} = p3
    # end

    test "update_all with no entries" do
      assert %Post{id: id1} = Repo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = Repo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = Repo.insert!(%Post{title: "ghi"})

      assert {0, []} =
               Repo.update_all(from(p in Post, where: p.title == "jkl"), set: [title: "123"])

      assert %Post{title: "abc"} = Repo.get(Post, id1)
      assert %Post{title: "def"} = Repo.get(Post, id2)
      assert %Post{title: "ghi"} = Repo.get(Post, id3)
    end

    test "update_all increment syntax" do
      assert %Post{id: id1} = Repo.insert!(%Post{title: "abc", views: 0})
      assert %Post{id: id2} = Repo.insert!(%Post{title: "def", views: 1})

      # Positive increment
      assert {2, []} = Repo.update_all(Post, inc: [views: 5])

      assert %Post{views: 5} = Repo.get(Post, id1)
      assert %Post{views: 6} = Repo.get(Post, id2)

      # Negative increment
      assert {2, []} = Repo.update_all(Post, inc: [views: -1])

      assert %Post{views: 4} = Repo.get(Post, id1)
      assert %Post{views: 5} = Repo.get(Post, id2)
    end

    test "update_all in query" do
      assert %Post{id: id1} = Repo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = Repo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = Repo.insert!(%Post{title: "ghi"})

      assert {3, []} = Repo.update_all(from(p in Post, update: [set: [title: "123"]]), [])

      assert %Post{title: "123"} = Repo.get(Post, id1)
      assert %Post{title: "123"} = Repo.get(Post, id2)
      assert %Post{title: "123"} = Repo.get(Post, id3)
    end

    test "update_all with casting and dumping" do
      title = "abc"
      inserted_at = ~N[2021-01-02 03:04:05]
      assert %Post{id: id} = Repo.insert!(%Post{})

      assert {1, []} = Repo.update_all(Post, set: [title: title, inserted_at: inserted_at])
      assert %Post{title: ^title, inserted_at: ^inserted_at} = Repo.get(Post, id)
    end
  end

  describe "delete_all/3" do
    test "regular delete_all" do
      assert %Post{} = Repo.insert!(%Post{title: "abc", text: "cba"})
      assert %Post{} = Repo.insert!(%Post{title: "def", text: "fed"})
      assert %Post{} = Repo.insert!(%Post{title: "ghi", text: "ihg"})

      assert {3, []} = Repo.delete_all(Post)
      assert [] = Repo.all(Post)
    end

    test "delete_all with filter" do
      assert %Post{} = Repo.insert!(%Post{title: "abc", text: "cba"})
      assert %Post{} = Repo.insert!(%Post{title: "def", text: "fed"})
      assert %Post{} = Repo.insert!(%Post{title: "ghi", text: "ihg"})

      assert {2, []} =
               Repo.delete_all(from(p in Post, where: p.title == "abc" or p.title == "def"))

      assert [%Post{}] = Repo.all(Post)
    end

    test "delete_all with no entries" do
      assert %Post{id: id1} = Repo.insert!(%Post{title: "abc", text: "cba"})
      assert %Post{id: id2} = Repo.insert!(%Post{title: "def", text: "fed"})
      assert %Post{id: id3} = Repo.insert!(%Post{title: "ghi", text: "ihg"})

      assert {0, []} = Repo.delete_all(from(p in Post, where: p.title == "jkl"))
      assert %Post{title: "abc"} = Repo.get(Post, id1)
      assert %Post{title: "def"} = Repo.get(Post, id2)
      assert %Post{title: "ghi"} = Repo.get(Post, id3)
    end
  end

  test "virtual fields" do
    assert %Post{id: id} = Repo.insert!(%Post{title: "abc", text: "cba"})
    assert Repo.get(Post, id).virt == "iamavirtualfield"
  end

  # TODO: Add advanced querying tests
end
