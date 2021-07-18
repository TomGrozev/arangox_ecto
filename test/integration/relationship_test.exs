defmodule ArangoxEctoTest.Integration.RelationshipTest do
  use ExUnit.Case

  alias ArangoXEctoTest.Repo
  alias ArangoXEctoTest.Integration.{Post, User, UserPosts}

  @test_collections [
    users: 2,
    test_edge: 3,
    posts: 2,
    post_user: 3,
    user_user: 3,
    user_posts: 3,
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

  describe "many relationship" do
    test "create relationship with auto generated module" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      assert %{_from: ^user_id, _to: ^post_id} = ArangoXEcto.create_edge(Repo, user, post)

      assert [%{_from: ^user_id, _to: ^post_id}] =
               Repo.all(ArangoXEctoTest.Integration.Edges.PostUser)

      assert %User{__id__: ^user_id, posts: [%Post{__id__: ^post_id, title: "abc"}]} =
               Repo.preload(user, :posts)
    end

    test "create relationship with supplied module" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      # TODO: Maybe make specifying edge not required?
      assert %{_from: ^user_id, _to: ^post_id} =
               ArangoXEcto.create_edge(Repo, user, post, edge: UserPosts)

      assert [%{_from: ^user_id, _to: ^post_id}] = Repo.all(UserPosts)

      assert %User{__id__: ^user_id, posts_two: [%Post{__id__: ^post_id, title: "abc"}]} =
               Repo.preload(user, :posts_two)
    end

    test "create relationship with supplied module and custom field" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      assert %{_from: ^user_id, _to: ^post_id, type: "abc"} =
               ArangoXEcto.create_edge(Repo, user, post, edge: UserPosts, fields: %{type: "abc"})

      assert [%{_from: ^user_id, _to: ^post_id, type: "abc"}] = Repo.all(UserPosts)

      assert %User{__id__: ^user_id, posts_two: [%Post{__id__: ^post_id, title: "abc"}]} =
               Repo.preload(user, :posts_two)
    end

    test "create relationship with non existent edge field" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      edge = ArangoXEcto.create_edge(Repo, user, post, edge: UserPosts, fields: %{fake: "abc"})
      assert not Map.has_key?(edge, :fake)
      assert %{_from: ^user_id, _to: ^post_id} = edge

      assert [%{_from: ^user_id, _to: ^post_id}] = Repo.all(UserPosts)
    end

    test "relationship with reversed from and to" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      %{_from: ^post_id, _to: ^user_id} = ArangoXEcto.create_edge(Repo, post, user)

      assert [%{_from: ^post_id, _to: ^user_id}] =
               Repo.all(ArangoXEctoTest.Integration.Edges.PostUser)
    end

    test "relationship with reversed from and to and custom module" do
      user =
        %User{__id__: user_id} = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()

      post = %Post{__id__: post_id} = %Post{title: "abc"} |> Repo.insert!()

      %{_from: ^post_id, _to: ^user_id} =
        ArangoXEcto.create_edge(Repo, post, user, edge: UserPosts)

      assert [%{_from: ^post_id, _to: ^user_id}] = Repo.all(UserPosts)
    end
  end

  describe "one relationship" do
    test "one to other one" do
      post = %Post{title: "abc"}
      user = %User{first_name: "John", last_name: "Smith", best_post: post}

      assert %User{id: user_id, best_post: %Post{id: post_id}} = Repo.insert!(user)

      assert %User{id: ^user_id, best_post: %Post{id: ^post_id, title: "abc"}} =
               Repo.get(User, user_id) |> Repo.preload(:best_post)

      assert %Post{id: ^post_id, title: "abc", user: %User{id: ^user_id}} =
               Repo.get(User, user_id) |> Repo.preload(:best_post)
    end
  end
end
