defmodule ArangoxEctoTest.Integration.RelationshipTest do
  use ArangoXEcto.Integration.Case,
    write: ["users", "posts", "posts_users"]

  alias ArangoXEcto.Integration.TestRepo
  alias ArangoXEcto.Integration.{Post, User, UserPosts}

  describe "many relationship" do
    test "create edge connection" do
      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      attrs = %{
        first_name: "John",
        last_name: "Smith",
        posts: [post]
      }

      user =
        %User{__id__: user_id} =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> Ecto.Changeset.put_assoc(:posts_two, [post])
        |> TestRepo.insert!()

      assert [%{_from: ^user_id, _to: ^post_id}] =
               TestRepo.all(UserPosts)

      assert %User{__id__: ^user_id, posts_two: [%Post{__id__: ^post_id, title: "abc"}]} =
               TestRepo.preload(user, :posts_two)
    end

    test "create relationship with supplied module and custom field" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      assert %{_from: ^user_id, _to: ^post_id, type: "abc"} =
               ArangoXEcto.create_edge(TestRepo, user, post,
                 edge: UserPosts,
                 fields: %{type: "abc"}
               )

      assert [%{_from: ^user_id, _to: ^post_id, type: "abc"}] = TestRepo.all(UserPosts)
    end

    test "create relationship with non existent edge field" do
      user =
        %User{__id__: user_id} =
        %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> TestRepo.insert!()

      edge =
        ArangoXEcto.create_edge(TestRepo, user, post, edge: UserPosts, fields: %{fake: "abc"})

      assert not Map.has_key?(edge, :fake)
      assert %{_from: ^user_id, _to: ^post_id} = edge

      assert [%{_from: ^user_id, _to: ^post_id}] = TestRepo.all(UserPosts)
    end

    test "preload from and to" do
      user = %User{} = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()

      post = %Post{} = %Post{title: "abc"} |> TestRepo.insert!()

      ArangoXEcto.create_edge(TestRepo, post, user, edge: UserPosts)

      assert [%UserPosts{from: %Post{}}] = TestRepo.all(UserPosts) |> TestRepo.preload(:from)
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
