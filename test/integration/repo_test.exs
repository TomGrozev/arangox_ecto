defmodule ArangoXEcto.Integration.RepoTest do
  use ArangoXEcto.Integration.Case,
    write: ["users", "posts", "comments"]

  import Ecto.Query
  import ExUnit.CaptureLog

  alias ArangoXEcto.Integration.{DynamicRepo, TestRepo}
  alias ArangoXEcto.Integration.{Comment, Post, User}

  test "if the repo is already started" do
    assert {:error, {:already_started, _}} = TestRepo.start_link()
  end

  describe "types" do
    test "valid geojson struct" do
      location = %Geo.Point{coordinates: {100.0, 0.0}, srid: nil}

      {:ok, %User{location: loaded_location}} =
        %User{location: location}
        |> TestRepo.insert()

      assert loaded_location == location
    end

    test "custom type is loaded and dumped correctly" do
      assert {:ok, %User{gender: :other}} = TestRepo.insert(%User{gender: :other})
    end
  end

  describe "Repo.all/2" do
    test "fetches empty" do
      assert [] == TestRepo.all(User)
      assert [] == TestRepo.all(from(u in User))
    end

    test "fetch with in" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      assert [] = TestRepo.all(from(u in User, where: u.first_name in []))
      assert [] = TestRepo.all(from(u in User, where: u.first_name in ["a", "b", "3"]))

      assert [_] = TestRepo.all(from(u in User, where: u.first_name not in []))
      assert [_] = TestRepo.all(from(u in User, where: u.first_name in ["1", "John", "3"]))
    end

    test "fetch with select and ordering" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      %User{first_name: "Ben", last_name: "Owens"} |> TestRepo.insert!()

      assert ["Ben", "John"] =
               TestRepo.all(from(u in User, order_by: u.first_name, select: u.first_name))

      assert ["Owens", "Smith"] =
               TestRepo.all(from(u in User, order_by: u.first_name, select: u.last_name))

      assert [_] = TestRepo.all(from(u in User, where: u.last_name == "Smith", select: u.id))
    end

    test "fetch using collection name" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      assert [_] = TestRepo.all(from(u in "users", select: u.id))
    end

    test "query from non existent collection" do
      assert [] = DynamicRepo.all(from(a in "abc", select: a.id))

      # assert_raise Arangox.Error, ~r/collection or view not found/, fn ->
      #   TestRepo.all(from(a in "abc", select: a.id))
      # end
    end

    test "fetch count" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      %User{first_name: "Ben", last_name: "John"} |> TestRepo.insert!()

      assert [2] = TestRepo.all(from(u in User, select: count(u.id)))

      assert_raise Ecto.QueryError, ~r/can only have one field with count/, fn ->
        TestRepo.all(from(u in User, select: {count(u.first_name), count(u.id)}))
      end

      assert_raise Ecto.QueryError,
                   ~r/can't have count fields and non count fields together/,
                   fn ->
                     TestRepo.all(from(u in User, select: {u.first_name, count(u.id)}))
                   end
    end

    test "using ecto date functions" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      assert [%User{}] = TestRepo.all(from(u in User, where: u.inserted_at > ago(1, "hour")))

      assert [] = TestRepo.all(from(u in User, where: u.inserted_at < ago(1, "hour")))

      assert [%User{}] = TestRepo.all(from(u in User, where: u.inserted_at < from_now(1, "hour")))

      assert [] = TestRepo.all(from(u in User, where: u.inserted_at > from_now(1, "hour")))

      assert [%User{}] =
               TestRepo.all(
                 from(u in User,
                   where: u.inserted_at < datetime_add(^NaiveDateTime.utc_now(), 1, "day")
                 )
               )

      assert [] =
               TestRepo.all(
                 from(u in User,
                   where: u.inserted_at > datetime_add(^NaiveDateTime.utc_now(), 1, "day")
                 )
               )

      assert [%User{}] =
               TestRepo.all(
                 from(u in User,
                   where: u.inserted_at < date_add(^Date.utc_today(), 1, "day")
                 )
               )

      assert [] =
               TestRepo.all(
                 from(u in User,
                   where: u.inserted_at > date_add(^Date.utc_today(), 1, "day")
                 )
               )
    end
  end

  describe "Repo.aggregate/3" do
    test "can count" do
      %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      %User{first_name: "Ben", last_name: "John"} |> TestRepo.insert!()

      assert 2 = TestRepo.aggregate(User, :count)
    end

    test "empty collection" do
      assert 0 = TestRepo.aggregate(User, :count)
    end
  end

  describe "Repo.insert/2 and Repo.insert!/2" do
    test "can insert" do
      user = %User{first_name: "John", last_name: "Smith"}

      assert {:ok, %User{}} = TestRepo.insert(user)
      assert %User{} = TestRepo.insert!(user)
    end

    test "cannot insert missing required fields" do
      assert {:error, %Ecto.Changeset{}} = TestRepo.insert(User.changeset(%User{}, %{}))

      assert_raise Ecto.InvalidChangesetError, ~r/could not perform/, fn ->
        TestRepo.insert!(User.changeset(%User{}, %{}))
      end
    end

    test "creates collection if not exists" do
      comment = %Comment{text: "abc"}

      ArangoXEcto.Sandbox.unboxed_run(DynamicRepo, fn ->
        assert {:ok, %Comment{}} = DynamicRepo.insert(comment)

        DynamicRepo.delete_all(Comment)
      end)
    end

    test "creates collection if not exists with options" do
      comment = %Comment{text: "cba"}

      ArangoXEcto.Sandbox.unboxed_run(DynamicRepo, fn ->
        assert {:ok, %Comment{}} = DynamicRepo.insert(comment)

        assert {:ok, %Arangox.Response{body: %{"type" => 2, "keyOptions" => %{"type" => "uuid"}}}} =
                 ArangoXEcto.api_query(DynamicRepo, :get, "/_api/collection/comments/properties")

        DynamicRepo.delete_all(Comment)
      end)
    end

    test "creates collection if not exists with indexes" do
      comment = %Comment{text: "def"}

      ArangoXEcto.Sandbox.unboxed_run(DynamicRepo, fn ->
        assert {:ok, %Comment{}} = DynamicRepo.insert(comment)

        assert {:ok,
                %Arangox.Response{
                  body: %{"indexes" => [_, %{"fields" => ["text"], "unique" => true}]}
                }} = ArangoXEcto.api_query(DynamicRepo, :get, "/_api/index?collection=comments")

        assert {:ok,
                %Arangox.Response{
                  body: %{"keyOptions" => %{"type" => "uuid"}}
                }} =
                 ArangoXEcto.api_query(DynamicRepo, :get, "/_api/collection/comments/properties")

        DynamicRepo.delete_all(Comment)
      end)
    end

    test "can insert and fetch with timestamps" do
      datetime = NaiveDateTime.utc_now()
      assert %User{} = TestRepo.insert!(%User{inserted_at: datetime})

      assert [%{inserted_at: ^datetime}] = TestRepo.all(User)
    end

    test "can provide primary key" do
      user = %User{id: "123456", first_name: "John", last_name: "Smith"}

      assert {:ok, %User{}} = TestRepo.insert(user)

      user = %User{id: "654321", first_name: "John", last_name: "Smith"}
      assert %User{} = TestRepo.insert!(user)
    end

    test "upsert on_conflict and returning" do
      user = %User{id: "123456", first_name: "John", last_name: "Smith"}

      assert {:ok, %User{}} = TestRepo.insert(user)

      change = %User{id: "123456", age: 18}

      assert {:ok, %User{id: "123456", age: 18}} =
               TestRepo.insert(change, on_conflict: :replace_all, returning: true)
    end
  end

  describe "Repo.update/2 and Repo.update!/2" do
    test "can update" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      user = User.changeset(user, %{last_name: "Snow"})
      assert {:ok, %User{last_name: "Snow"}} = TestRepo.update(user)

      user = User.changeset(user, %{last_name: "Smith"})
      assert %User{last_name: "Smith"} = TestRepo.update!(user)
    end

    test "no change" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      changeset = User.changeset(user, %{})
      assert {:ok, user} = TestRepo.update(changeset)

      changeset = User.changeset(user, %{})
      assert ^user = TestRepo.update!(changeset)
    end

    test "cannot update removing required fields" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      changeset = User.changeset(user, %{last_name: nil})

      assert {:error, %Ecto.Changeset{}} = TestRepo.update(changeset)

      assert_raise Ecto.InvalidChangesetError, ~r/could not perform/, fn ->
        TestRepo.update!(changeset)
      end
    end

    test "returns extra fields" do
      %User{id: id} =
        %User{first_name: "John", last_name: "Smith", age: 10, gender: :female}
        |> TestRepo.insert!()

      user = User.changeset(%User{id: id}, %{first_name: "Bob", last_name: "Snow"})

      assert {:ok, %User{age: 10, last_name: "Snow"}} = TestRepo.update(user, returning: true)

      assert {:ok, %User{last_name: "Snow", age: 10, gender: :male}} =
               TestRepo.update(user, returning: [:age])

      assert {:ok, %User{age: 0, last_name: "Snow"}} = TestRepo.update(user, returning: false)
    end

    test "returns stale error when updating deleted" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      TestRepo.delete(user)

      user_change = User.changeset(user, %{first_name: "Bob", last_name: "Snow"})

      assert_raise Ecto.StaleEntryError, ~r/attempted to update a stale struct/, fn ->
        TestRepo.update!(user_change)
      end
    end

    test "can update when there is non _key index" do
      %Comment{id: "333", text: "alpha", extra: "beta"} |> TestRepo.insert!()

      assert {:ok, %Comment{id: "333", text: "alpha", extra: "charlie"}} =
               %Comment{
                 id: "333",
                 text: "alpha"
               }
               |> Ecto.Changeset.change(extra: "charlie")
               |> Ecto.Changeset.optimistic_lock(:text, fn c -> c end)
               |> TestRepo.update()
    end
  end

  describe "Repo.delete/2 and TestRepo.delete!/2" do
    test "can delete" do
      user = %User{first_name: "John", last_name: "Smith"}

      deleted_meta =
        user.__meta__
        |> Map.put(:state, :deleted)

      to_delete = TestRepo.insert!(user)

      assert {:ok, %User{__meta__: ^deleted_meta}} = TestRepo.delete(to_delete)

      to_delete = TestRepo.insert!(user)
      assert %User{__meta__: ^deleted_meta} = TestRepo.delete!(to_delete)
    end

    test "cannot delete non existent record" do
      user = %User{id: "123", first_name: "John", last_name: "Smith"}

      assert_raise Ecto.StaleEntryError, ~r/attempted to .* a stale struct/, fn ->
        TestRepo.delete(user)
      end

      assert_raise Ecto.StaleEntryError, ~r/attempted to .* a stale struct/, fn ->
        TestRepo.delete!(user)
      end
    end

    test "cannot delete un-inserted record" do
      user = %User{first_name: "John", last_name: "Smith"}

      assert_raise Ecto.NoPrimaryKeyValueError, ~r/struct .* is missing primary key value/, fn ->
        TestRepo.delete(user)
      end

      assert_raise Ecto.NoPrimaryKeyValueError, ~r/struct .* is missing primary key value/, fn ->
        TestRepo.delete!(user)
      end
    end
  end

  describe "unqiue constraints" do
    test "unique constraint" do
      changeset =
        User.changeset(%User{id: "1234", first_name: "Bob", last_name: "Bobington"}, %{})

      {:ok, _} = TestRepo.insert(changeset)

      exception =
        assert_raise Ecto.ConstraintError,
                     ~r/constraint error when attempting to insert struct/,
                     fn ->
                       changeset
                       |> TestRepo.insert!()
                     end

      assert exception.message =~ "constraint error when attempting to insert struct"
      assert exception.message =~ "The changeset has not defined any constraint."
    end

    test "custom unique constraint" do
      changeset =
        User.changeset(%User{id: "1234", first_name: "Bob", last_name: "Bobington"}, %{})

      {:ok, _} = TestRepo.insert(changeset)

      exception =
        assert_raise Ecto.ConstraintError,
                     ~r/constraint error when attempting to insert struct/,
                     fn ->
                       changeset
                       |> Ecto.Changeset.unique_constraint(:id, name: :test_constraint)
                       |> TestRepo.insert!()
                     end

      assert exception.message =~ "\"test_constraint\" (unique_constraint)"
    end

    test "named unique constraint" do
      changeset =
        Ecto.Changeset.cast(%Comment{}, %{text: "hello"}, [:text])
        |> Ecto.Changeset.unique_constraint(:text, name: "idx_comments_text")

      TestRepo.insert!(changeset)

      assert {:error,
              %{
                errors: [
                  {
                    :text,
                    {"has already been taken",
                     [constraint: :unique, constraint_name: "idx_comments_text"]}
                  }
                ]
              }} = TestRepo.insert(changeset)
    end
  end

  describe "Repo.get/3 and TestRepo.get!/3" do
    test "get items" do
      user = TestRepo.insert!(%User{first_name: "John", last_name: "Smith"})
      post = TestRepo.insert!(%Post{title: "My Blog"})

      assert user == TestRepo.get(User, user.id)
      # with casting
      assert post == TestRepo.get(Post, to_string(post.id))

      assert user == TestRepo.get!(User, user.id)
      # with casting
      assert post == TestRepo.get!(Post, to_string(post.id))
    end

    test "can't get non existent" do
      assert nil == TestRepo.get(User, "1")

      assert_raise Ecto.NoResultsError, fn ->
        TestRepo.get!(Post, "1")
      end
    end
  end

  describe "Repo.get_by/3 and TestRepo.get_by!/3" do
    test "get items" do
      user = TestRepo.insert!(%User{first_name: "John", last_name: "Smith"})
      post = TestRepo.insert!(%Post{title: "My Blog"})

      assert user == TestRepo.get_by(User, id: user.id)
      assert user == TestRepo.get_by(User, first_name: user.first_name)
      assert user == TestRepo.get_by(User, id: user.id, first_name: user.first_name)
      # with casting
      assert post == TestRepo.get_by(Post, id: to_string(post.id))

      assert user == TestRepo.get_by!(User, id: user.id)
      assert user == TestRepo.get_by!(User, first_name: user.first_name)
      assert user == TestRepo.get_by!(User, id: user.id, first_name: user.first_name)
      # with casting
      assert post == TestRepo.get_by!(Post, id: to_string(post.id))
    end

    test "can't find wrong values" do
      post = TestRepo.insert!(%Post{title: "My Blog"})

      assert nil == TestRepo.get_by(Post, title: "abc")
      assert nil == TestRepo.get_by(Post, id: post.id, title: "abc")

      assert_raise Ecto.NoResultsError, fn ->
        TestRepo.get_by!(Post, id: "1", title: "hello")
      end
    end
  end

  describe "first, last and one / one!" do
    test "first" do
      user1 = TestRepo.insert!(%User{first_name: "John", last_name: "Smith"})
      user2 = TestRepo.insert!(%User{first_name: "Ben", last_name: "Bark"})

      assert user1 == User |> first |> TestRepo.one()

      assert user2 == from(u in User, order_by: u.first_name) |> first |> TestRepo.one()

      assert user1 == from(u in User, order_by: [desc: u.first_name]) |> first |> TestRepo.one()

      query = from(u in User, where: is_nil(u.id))
      refute query |> first |> TestRepo.one()

      assert_raise Ecto.NoResultsError, fn ->
        query |> first |> TestRepo.one!()
      end
    end

    test "last" do
      user1 = TestRepo.insert!(%User{first_name: "John", last_name: "Smith"})
      user2 = TestRepo.insert!(%User{first_name: "Ben", last_name: "Bark"})

      assert user2 == User |> last |> TestRepo.one()

      assert user1 == from(u in User, order_by: u.first_name) |> last |> TestRepo.one()

      assert user2 == from(u in User, order_by: [desc: u.first_name]) |> last |> TestRepo.one()

      query = from(u in User, where: is_nil(u.id))
      refute query |> last |> TestRepo.one()

      assert_raise Ecto.NoResultsError, fn ->
        query |> last |> TestRepo.one!()
      end
    end
  end

  describe "insert_all/3" do
    test "regular insert_all" do
      assert {2, nil} = TestRepo.insert_all(Post, [[title: "abc"], %{title: "cba"}])

      assert {2, nil} = TestRepo.insert_all({"posts", Post}, [[title: "def"], %{title: "fed"}])

      assert [%Post{title: "abc"}, %Post{title: "cba"}, %Post{title: "def"}, %Post{title: "fed"}] =
               TestRepo.all(Post |> order_by(:title))
    end

    test "insert_all with no fields" do
      assert {2, nil} = TestRepo.insert_all(Post, [[], []])
      assert [%Post{}, %Post{}] = TestRepo.all(Post)
    end

    test "insert_all no objects" do
      assert {0, nil} = TestRepo.insert_all("posts", [])
      assert {0, nil} = TestRepo.insert_all({"posts", Post}, [])
    end

    test "insert_all with invalid ids" do
      assert {0, nil} = TestRepo.insert_all(Post, [[id: nil, title: "abc"]])
    end

    @tag :returning
    test "insert_all with returning schema" do
      assert {0, []} = TestRepo.insert_all(Post, [], returning: true)
      assert {0, nil} = TestRepo.insert_all(Post, [], returning: false)
    end

    @tag :returning
    test "insert_all with returning some fields" do
      {2, [p1, p2]} =
        TestRepo.insert_all(Post, [[title: "abc"], [title: "cba"]], returning: [:id, :title])

      assert %Post{title: "abc", __meta__: %{state: :loaded}} = p1
      assert %Post{title: "cba", __meta__: %{state: :loaded}} = p2
    end

    @tag :returning
    test "insert_all with returning all fields" do
      {2, [p1, p2]} = TestRepo.insert_all(Post, [[title: "abc"], [title: "cba"]], returning: true)

      assert %Post{title: "abc", __meta__: %{state: :loaded}} = p1
      assert %Post{title: "cba", __meta__: %{state: :loaded}} = p2
    end

    test "insert_all with dumping" do
      datetime = ~N[2021-01-01 01:20:30.000000]
      assert {2, nil} = TestRepo.insert_all(Post, [%{inserted_at: datetime}, %{title: "abc"}])

      assert [%Post{inserted_at: ^datetime, title: nil}, %Post{inserted_at: nil, title: "abc"}] =
               TestRepo.all(Post |> order_by(:title))
    end

    test "on_conflict insert_all" do
      assert {2, nil} =
               TestRepo.insert_all(Post, [[id: "123", title: "abc"], [id: "123", title: "abc"]],
                 on_conflict: :replace_all
               )

      assert [%Post{id: "123", title: "abc"}] = TestRepo.all(Post |> order_by(:title))
    end
  end

  describe "update_all/3" do
    test "regular updates" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "ghi"})

      assert {0, []} =
               TestRepo.update_all(
                 from(p in Post, where: false, select: [:id]),
                 set: [title: "123"]
               )

      assert {3, []} = TestRepo.update_all(Post, set: [title: "123"])

      assert %Post{title: "123"} = TestRepo.get(Post, id1)
      assert %Post{title: "123"} = TestRepo.get(Post, id2)
      assert %Post{title: "123"} = TestRepo.get(Post, id3)
    end

    # `:returning` attribute no longer is included in query evaluation
    # I am unlikely to implement this features as it would require a rework of some code. PRs are welcome.
    # @tag :returning
    # test "update_all with returning" do
    #  assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc"})
    #  assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def"})
    #  assert %Post{id: id3} = TestRepo.insert!(%Post{title: "ghi"})

    #  assert {3, posts} = TestRepo.update_all(Post, [set: [title: "123"]], returning: true)

    #  [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    #  assert %Post{id: ^id1, title: "123"} = p1
    #  assert %Post{id: ^id2, title: "123"} = p2
    #  assert %Post{id: ^id3, title: "123"} = p3

    #  assert {3, posts} = TestRepo.update_all(Post, [set: [text: "hello"]], returning: [:id, :text])

    #  [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    #  assert %Post{id: ^id1, title: nil, text: "hello"} = p1
    #  assert %Post{id: ^id2, title: nil, text: "hello"} = p2
    #  assert %Post{id: ^id3, title: nil, text: "hello"} = p3
    # end

    test "update_all with no entries" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "ghi"})

      assert {0, []} =
               TestRepo.update_all(from(p in Post, where: p.title == "jkl"), set: [title: "123"])

      assert %Post{title: "abc"} = TestRepo.get(Post, id1)
      assert %Post{title: "def"} = TestRepo.get(Post, id2)
      assert %Post{title: "ghi"} = TestRepo.get(Post, id3)
    end

    test "update_all increment syntax" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc", visits: 0})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def", visits: 1})

      # Positive increment
      assert {2, []} = TestRepo.update_all(Post, inc: [visits: 5])

      assert %Post{visits: 5} = TestRepo.get(Post, id1)
      assert %Post{visits: 6} = TestRepo.get(Post, id2)

      # Negative increment
      assert {2, []} = TestRepo.update_all(Post, inc: [visits: -1])

      assert %Post{visits: 4} = TestRepo.get(Post, id1)
      assert %Post{visits: 5} = TestRepo.get(Post, id2)
    end

    test "update_all in query" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "ghi"})

      assert {3, []} = TestRepo.update_all(from(p in Post, update: [set: [title: "123"]]), [])

      assert %Post{title: "123"} = TestRepo.get(Post, id1)
      assert %Post{title: "123"} = TestRepo.get(Post, id2)
      assert %Post{title: "123"} = TestRepo.get(Post, id3)
    end

    test "update_all with casting and dumping" do
      title = "abc"
      inserted_at = ~N[2021-01-02 03:04:05]
      assert %Post{id: id} = TestRepo.insert!(%Post{})

      assert {1, []} = TestRepo.update_all(Post, set: [title: title, inserted_at: inserted_at])
      assert %Post{title: ^title, inserted_at: ^inserted_at} = TestRepo.get(Post, id)
    end
  end

  describe "delete_all/3" do
    test "regular delete_all" do
      assert %Post{} = TestRepo.insert!(%Post{title: "abc", intensity: 1.0})
      assert %Post{} = TestRepo.insert!(%Post{title: "def", intensity: 2.1})
      assert %Post{} = TestRepo.insert!(%Post{title: "ghi", intensity: 3.2})

      assert {3, []} = TestRepo.delete_all(Post)
      assert [] = TestRepo.all(Post)
    end

    test "delete_all with filter" do
      assert %Post{} = TestRepo.insert!(%Post{title: "abc", intensity: 1.0})
      assert %Post{} = TestRepo.insert!(%Post{title: "def", intensity: 2.1})
      assert %Post{} = TestRepo.insert!(%Post{title: "ghi", intensity: 3.2})

      assert {2, []} =
               TestRepo.delete_all(from(p in Post, where: p.title == "abc" or p.title == "def"))

      assert [%Post{}] = TestRepo.all(Post)
    end

    test "delete_all with no entries" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "abc", intensity: 1.0})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "def", intensity: 2.1})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "ghi", intensity: 3.2})

      assert {0, []} = TestRepo.delete_all(from(p in Post, where: p.title == "jkl"))
      assert %Post{title: "abc"} = TestRepo.get(Post, id1)
      assert %Post{title: "def"} = TestRepo.get(Post, id2)
      assert %Post{title: "ghi"} = TestRepo.get(Post, id3)
    end
  end

  describe "transactions" do
    test "can do multi operation with transaction" do
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:post, %Post{title: "my new post"})
        |> Ecto.Multi.all(:all_posts, Post)
        |> TestRepo.transaction(write: Post)

      assert {:ok, %{post: post, all_posts: [post]}} = result
    end

    test "can rollback" do
      ArangoXEcto.Sandbox.unboxed_run(TestRepo, fn ->
        assert [] = TestRepo.all(Post)

        assert {:error, :rollback} =
                 TestRepo.transaction(
                   fn ->
                     assert %Post{} = TestRepo.insert!(%Post{title: "my other new post"})

                     TestRepo.rollback(:rollback)
                   end,
                   write: [Post]
                 )

        assert [] = TestRepo.all(Post)
      end)
    end

    test "stream" do
      assert %Post{} = TestRepo.insert!(%Post{title: "my new post"})

      query =
        from(p in Post,
          select: p.title
        )

      stream = TestRepo.stream(query)

      assert {:ok, ["my new post"]} =
               TestRepo.transaction(fn ->
                 Enum.to_list(stream)
               end)
    end
  end

  describe "checkout" do
    test "can checkout" do
      refute TestRepo.checked_out?()

      TestRepo.checkout(fn ->
        assert TestRepo.checked_out?()
      end)

      refute TestRepo.checked_out?()
    end
  end

  test "supports types" do
    user = %User{
      uuid: "db7af35b-5312-41d0-8a8f-350b515a2286",
      create_time: Time.utc_now(),
      create_datetime: DateTime.utc_now()
    }

    assert {:ok, %User{}} = TestRepo.insert(user)
  end

  describe "logging level" do
    test "setting level" do
      assert capture_log(fn -> TestRepo.all(User) end) == ""

      assert capture_log(fn -> TestRepo.all(User, log: :info) end) =~ "[info] QUERY OK"
      assert capture_log(fn -> TestRepo.all(User, log: :error) end) =~ "[error] QUERY OK"
    end

    test "setting true level" do
      assert capture_log(fn -> TestRepo.all(User) end) == ""

      # Won't log because debug level is false which it defaults back to
      assert capture_log(fn -> TestRepo.all(User, log: true) end) == ""
    end
  end

  test "exists?" do
    assert %Post{id: id} = TestRepo.insert!(%Post{title: "abc", intensity: 1.1})
    assert TestRepo.exists?(from(p in Post, where: p.id == ^id))
    refute TestRepo.exists?(from(p in Post, where: p.id == ^"unexisting id"))
  end

  @tag :focus
  test "unsafe_validate_unique" do
    import Ecto.Changeset

    TestRepo.insert!(%Post{title: "abc", intensity: 1.1})

    assert %Ecto.Changeset{
             valid?: false,
             errors: [
               title: {"has already been taken", [validation: :unsafe_unique, fields: [:title]]}
             ]
           } =
             %Post{}
             |> cast(%{title: "abc"}, [:title])
             |> unsafe_validate_unique(:title, TestRepo)

    assert %Ecto.Changeset{valid?: true} =
             %Post{}
             |> cast(%{title: "new title"}, [:title])
             |> unsafe_validate_unique(:title, TestRepo)
  end
end
