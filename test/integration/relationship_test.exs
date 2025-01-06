defmodule ArangoxEctoTest.Integration.RelationshipTest do
  use ArangoXEcto.Integration.Case,
    write: ["users", "posts", "comments", "posts_users", "user_content"]

  alias ArangoXEcto.Integration.TestRepo
  alias ArangoXEcto.Integration.{Comment, Post, User, UserContent, UserPosts}

  describe "many relationship" do
    test "cast edge connection" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        posts_two: [
          %{title: "abc"}
        ]
      }

      post_changeset = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:title])
      end

      %User{id: user_id} =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> Ecto.Changeset.cast_assoc(:posts_two, with: post_changeset)
        |> TestRepo.insert!()

      assert %User{id: ^user_id, posts_two: [%{title: "abc"}]} =
               TestRepo.get(User, user_id) |> TestRepo.preload(:posts_two)

      assert %User{id: ^user_id, posts_two: [%Post{title: "abc"}]} =
               TestRepo.get(User, user_id) |> ArangoXEcto.preload(TestRepo, :posts_two)
    end

    test "cast edge polymorphic connection" do
      user1_attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: "cba"},
          %{title: "abc"}
        ]
      }

      user2_attrs = %{
        first_name: "Bob",
        last_name: "Smith",
        my_content: [
          %{text: "abc"},
          %{title: "cba"}
        ]
      }

      %User{id: user_id} = insert_user(user1_attrs)

      [post] = TestRepo.all(Post)
      [comment] = TestRepo.all(Comment)

      insert_user(user2_attrs)

      assert %User{id: ^user_id, my_content: [%{title: "abc"}, %{text: "cba"}]} =
               TestRepo.get(User, user_id) |> TestRepo.preload(:my_content)

      assert %User{id: ^user_id, my_content: [^post, ^comment]} =
               TestRepo.get(User, user_id) |> ArangoXEcto.preload(TestRepo, :my_content)
    end

    defp insert_user(attrs) do
      post_changeset = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:title])
      end

      comment_changeset = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:text])
      end

      Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
      |> ArangoXEcto.Changeset.cast_graph(:my_content,
        with: %{
          Post => post_changeset,
          Comment => comment_changeset
        }
      )
      |> TestRepo.insert!()
    end

    test "put edge connection" do
      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()
      post2 = %Post{__id__: post2_id} = %Post{title: "cba"} |> TestRepo.insert!()

      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      user =
        %User{__id__: user_id} =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.put_graph(:posts_two, [post])
        |> TestRepo.insert!()

      assert [%{_from: ^user_id, _to: ^post_id}] = TestRepo.all(UserPosts)

      assert %User{__id__: ^user_id, posts_two: [%Post{__id__: ^post_id, title: "abc"}]} =
               TestRepo.preload(user, :posts_two)

      user =
        user
        |> Ecto.Changeset.cast(%{}, [])
        |> ArangoXEcto.Changeset.put_graph(:posts_two, [post2])
        |> TestRepo.update!()

      assert [%{_from: ^user_id, _to: ^post2_id}] = TestRepo.all(UserPosts)

      assert %User{__id__: ^user_id, posts_two: [%Post{__id__: ^post2_id, title: "cba"}]} =
               TestRepo.preload(user, :posts_two)
    end

    test "create relationship with supplied module and custom field" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      assert %{_from: ^post_id, _to: ^user_id, type: "abc"} =
               ArangoXEcto.create_edge(TestRepo, post, user,
                 edge: UserPosts,
                 fields: %{type: "abc"}
               )

      assert [%{_from: ^post_id, _to: ^user_id, type: "abc"}] = TestRepo.all(UserPosts)
    end

    test "cannot reverse from and to on edge relationship" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      assert %{_from: ^post_id, _to: ^user_id} =
               ArangoXEcto.create_edge(TestRepo, post, user, edge: UserPosts)

      assert_raise Ecto.InvalidChangesetError,
                   ~r/from schema is not in the available from schemas.*to schema is not in the available to schemas/is,
                   fn ->
                     ArangoXEcto.create_edge(TestRepo, user, post, edge: UserPosts)
                   end
    end

    test "create relationship with non existent edge field" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      edge =
        ArangoXEcto.create_edge(TestRepo, post, user, edge: UserPosts, fields: %{fake: "abc"})

      assert not Map.has_key?(edge, :fake)
      assert %{_from: ^post_id, _to: ^user_id} = edge

      assert [%{_from: ^post_id, _to: ^user_id}] = TestRepo.all(UserPosts)
    end

    test "create relationship with multiple types of from and to" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()
      comment = %Comment{__id__: comment_id} = %Comment{text: "cba"} |> TestRepo.insert!()

      assert %{_from: ^user_id, _to: ^post_id} =
               ArangoXEcto.create_edge(TestRepo, user, post, edge: UserContent)

      assert %{_from: ^user_id, _to: ^comment_id} =
               ArangoXEcto.create_edge(TestRepo, user, comment, edge: UserContent)

      assert %{my_posts: [^post]} = ArangoXEcto.preload(user, TestRepo, :my_posts)
      assert %{my_comments: [^comment]} = ArangoXEcto.preload(user, TestRepo, :my_comments)
    end
  end

  describe "one relationship" do
    test "one to other one" do
      post = %Post{title: "abc"}
      user = %User{first_name: "John", last_name: "Smith", best_post: post}

      assert %User{id: user_id, best_post: %Post{id: post_id}} = TestRepo.insert!(user)

      assert %User{id: ^user_id, best_post: %Post{id: ^post_id, title: "abc"}} =
               TestRepo.get(User, user_id) |> TestRepo.preload(:best_post)

      assert %Post{id: ^post_id, title: "abc", user: %User{id: ^user_id}} =
               TestRepo.get(Post, post_id) |> TestRepo.preload(:user)
    end
  end
end
