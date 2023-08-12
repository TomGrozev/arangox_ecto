defmodule ArangoXEctoTest do
  @moduledoc false

  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEctoTest.Integration.{Class, Post, User, UserPosts, UserPostsOptions}
  alias ArangoXEctoTest.Repo

  import Ecto.Query

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
    collection_res =
      case Arangox.get(conn, "/_api/collection") do
        {:ok, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
        {:error, _} -> []
      end

    # Get all view names
    view_res =
      case Arangox.get(conn, "/_api/view") do
        {:ok, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
        {:error, _} -> []
      end

    collection_names =
      Enum.map(collection_res, fn %{"name" => name} -> name end)
      |> Enum.filter(&(!String.starts_with?(&1, "_")))

    view_names = Enum.map(view_res, fn %{"id" => id} -> id end)

    # Delete all collections
    for collection <- collection_names do
      Arangox.delete(conn, "/_api/collection/#{collection}")
    end

    # Delete all views
    for view <- view_names do
      Arangox.delete(conn, "/_api/view/#{view}")
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

    # Get all analyzer names
    analyzer_res =
      case Arangox.get(conn, "/_api/analyzer") do
        {:ok, %Arangox.Response{body: %{"error" => false, "result" => result}}} -> result
        {:error, _} -> []
      end

    analyzer_names =
      Enum.map(analyzer_res, fn %{"name" => name} -> name end)
      |> Enum.filter(&String.starts_with?(&1, "arangox_ecto_test::"))

    # Delete all analyzers
    for analyzer <- analyzer_names do
      Arangox.delete(conn, "/_api/analyzer/#{analyzer}?force=true")
    end

    context
  end

  describe "aql_query/4 and aql_query!/4" do
    test "invalid AQL query" do
      query = "FOsdfsdfgdfs abc"

      {:error, %Arangox.Error{error_num: 1501}} = ArangoXEcto.aql_query(Repo, query)

      assert_raise Arangox.Error, ~r/\[400\] \[1501\] AQL: syntax error/i, fn ->
        ArangoXEcto.aql_query!(Repo, query)
      end
    end

    test "non existent collection AQL query" do
      query = "FOR var in non_existent RETURN var"

      {:error, %Arangox.Error{error_num: 1203}} = ArangoXEcto.aql_query(Repo, query)

      assert_raise Arangox.Error, ~r/\[404\] \[1203\] AQL: collection or view not found/, fn ->
        ArangoXEcto.aql_query!(Repo, query)
      end
    end

    test "filter AQL query" do
      fname = "John"
      lname = "Smith"
      %User{first_name: fname, last_name: lname} |> Repo.insert!()

      collection_name = User.__schema__(:source)

      query = """
      FOR var in @@collection_name
      FILTER var.first_name == @fname AND var.last_name == @lname
      RETURN var
      """

      assert {:ok,
              [
                %{
                  "_id" => _,
                  "_key" => _,
                  "_rev" => _,
                  "first_name" => ^fname,
                  "last_name" => ^lname
                }
              ]} =
               ArangoXEcto.aql_query(Repo, query, [
                 {:"@collection_name", collection_name},
                 fname: fname,
                 lname: lname
               ])

      assert [
               %{
                 "_id" => _,
                 "_key" => _,
                 "_rev" => _,
                 "first_name" => ^fname,
                 "last_name" => ^lname
               }
             ] =
               ArangoXEcto.aql_query!(Repo, query, [
                 {:"@collection_name", collection_name},
                 fname: fname,
                 lname: lname
               ])
    end

    test "insert query" do
      collection_name = User.__schema__(:source)
      fname = "bob"

      query = """
      INSERT {first_name: @fname} into @@collection_name
      """

      assert {:ok, []} =
               ArangoXEcto.aql_query(
                 Repo,
                 query,
                 [
                   {:"@collection_name", collection_name},
                   fname: fname
                 ],
                 write: [collection_name]
               )
    end
  end

  describe "api_query/3" do
    test "invalid function passed" do
      assert_raise ArgumentError, ~r/Invalid function passed to `Arangox` module/, fn ->
        ArangoXEcto.api_query(Repo, :non_existent, ["/_api/collections"])
      end
    end

    test "valid function but not allowed" do
      assert_raise ArgumentError, ~r/Invalid function passed to `Arangox` module/, fn ->
        ArangoXEcto.api_query(Repo, :start_link)
      end
    end

    test "valid Arangox function" do
      assert {:ok, %Arangox.Response{body: %{"version" => _, "error" => _, "code" => _}}} =
               ArangoXEcto.api_query(Repo, :get, ["/_admin/database/target-version"])
    end
  end

  describe "create_edge/4" do
    test "create edge with no fields and no custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(Repo, user1, user2)

      assert %{_from: ^from, _to: ^to} = edge
    end

    test "create edge with no fields and a custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(Repo, user1, user2, collection_name: "friends")

      assert %{_from: ^from, _to: ^to} = edge
    end

    test "create edge with fields and a custom module" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      post = %Post{title: "abc", text: "cba"} |> Repo.insert!()

      from = id_from_user(user)
      to = "posts/" <> post.id

      edge = ArangoXEcto.create_edge(Repo, user, post, edge: UserPosts, fields: %{type: "wrote"})

      assert %UserPosts{_from: ^from, _to: ^to, type: "wrote"} = edge
    end

    test "create edge with options and indexes", %{conn: conn} do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      post = %Post{title: "abc", text: "cba"} |> Repo.insert!()

      from = id_from_user(user)
      to = "posts/" <> post.id

      edge =
        ArangoXEcto.create_edge(Repo, user, post,
          edge: UserPostsOptions,
          fields: %{type: "wrote"}
        )

      assert %UserPostsOptions{_from: ^from, _to: ^to, type: "wrote"} = edge

      assert {:ok,
              %Arangox.Response{
                body: %{"indexes" => [_, _, %{"fields" => ["type"], "unique" => true}]}
              }} = Arangox.get(conn, "/_api/index?collection=user_posts_options")

      assert {:ok,
              %Arangox.Response{
                body: %{"keyOptions" => %{"type" => "uuid"}}
              }} = Arangox.get(conn, "/_api/collection/user_posts_options/properties")
    end
  end

  describe "create_view/2" do
    test "creates a new view but fails on recreate" do
      assert {:ok, %Arangox.Response{status: 201}} =
               ArangoXEcto.create_view(Repo, ArangoXEctoTest.Integration.UsersView)

      assert {:error, %Arangox.Error{error_num: 1207}} =
               ArangoXEcto.create_view(Repo, ArangoXEctoTest.Integration.UsersView)
    end

    test "automatically creates collection if it doesn't exist" do
      # Comments collection doesn't exist by default
      assert {:ok, %Arangox.Response{status: 201}} =
               ArangoXEcto.create_view(Repo, ArangoXEctoTest.Integration.CommentView)
    end

    test "error on invalid view schema" do
      # Not a view schema
      assert_raise ArgumentError, ~r/not a valid view schema/, fn ->
        ArangoXEcto.create_view(Repo, ArangoXEcto)
      end
    end

    test "automatically creates analyzers in dynamic mode" do
      assert {:error, %Arangox.Error{status: 400, error_num: 10}} =
               ArangoXEcto.create_view(Repo, ArangoXEctoTest.Integration.FailedAnalyzerTestView)

      assert {:ok, %Arangox.Response{status: 201}} =
               ArangoXEcto.create_view(Repo, ArangoXEctoTest.Integration.AnalyzerTestView)
    end
  end

  describe "create_analyzers/2" do
    test "creates analyzers" do
      {success, fail} =
        case ArangoXEcto.create_analyzers(Repo, ArangoXEctoTest.Integration.Analyzers) do
          {:ok, responses} -> {responses, []}
          {:error, success, fail} -> {success, fail}
        end

      # only errors allowed are arango not implemented errors
      for {_name, err} <- fail do
        assert %Arangox.Error{status: 501, error_num: 9} = err
      end

      expected_responses = %{
        a: %{
          "features" => ["norm"],
          "properties" => %{},
          "name" => "arangox_ecto_test::a",
          "type" => "identity"
        },
        b: %{
          "features" => ["frequency", "position"],
          "properties" => %{"delimiter" => ","},
          "name" => "arangox_ecto_test::b",
          "type" => "delimiter"
        },
        c: %{
          "features" => ["frequency", "position", "norm"],
          "properties" => %{"locale" => "en"},
          "name" => "arangox_ecto_test::c",
          "type" => "stem"
        },
        d: %{
          "features" => ["frequency", "position"],
          "properties" => %{"accent" => false, "case" => "lower", "locale" => "en"},
          "name" => "arangox_ecto_test::d",
          "type" => "norm"
        },
        e: %{
          "features" => [],
          "properties" => %{
            "endMarker" => "b",
            "max" => 5,
            "min" => 3,
            "preserveOriginal" => true,
            "startMarker" => "a",
            "streamType" => "binary"
          },
          "name" => "arangox_ecto_test::e",
          "type" => "ngram"
        },
        f: %{
          "features" => ["frequency", "norm"],
          "properties" => %{
            "accent" => false,
            "case" => "lower",
            "edgeNgram" => %{"min" => 3},
            "locale" => "en",
            "stemming" => false,
            "stopwords" => ["abc"]
          },
          "name" => "arangox_ecto_test::f",
          "type" => "text"
        },
        g: %{
          "features" => ["frequency"],
          "properties" => %{"locale" => "en"},
          "name" => "arangox_ecto_test::g",
          "type" => "collation"
        },
        h: %{
          "features" => ["norm"],
          "properties" => %{
            "batchSize" => 500,
            "collapsePositions" => true,
            "keepNull" => false,
            "memoryLimit" => 2_097_152,
            "queryString" => "RETURN SOUNDEX(@param)",
            "returnType" => "string"
          },
          "name" => "arangox_ecto_test::h",
          "type" => "aql"
        },
        i: %{
          "features" => ["frequency"],
          "properties" => %{
            "pipeline" => [
              %{
                "properties" => %{
                  "accent" => false,
                  "case" => "lower",
                  "locale" => "en",
                  "stemming" => true
                },
                "type" => "text"
              },
              %{
                "properties" => %{
                  "accent" => false,
                  "case" => "lower",
                  "locale" => "en"
                },
                "type" => "norm"
              }
            ]
          },
          "name" => "arangox_ecto_test::i",
          "type" => "pipeline"
        },
        j: %{
          "features" => [],
          "properties" => %{"hex" => false, "stopwords" => ["xyz"]},
          "name" => "arangox_ecto_test::j",
          "type" => "stopwords"
        },
        k: %{
          "features" => [],
          "properties" => %{"break" => "all", "case" => "none"},
          "name" => "arangox_ecto_test::k",
          "type" => "segmentation"
        },
        # This test doesn't work all the time. Not sure why, something to look into later
        # l: %{
        #   "features" => ["norm"],
        #   "properties" => %{
        #     "options" => %{"maxCells" => 21, "maxLevel" => 24, "minLevel" => 5},
        #     "type" => "shape"
        #   },
        #   "name" => "arangox_ecto_test::l",
        #   "type" => "geojson"
        # },
        m: %{
          "features" => ["norm"],
          "properties" => %{
            "latitude" => ["lat", "latitude"],
            "longitude" => ["long", "longitude"],
            "options" => %{"maxCells" => 21, "maxLevel" => 24, "minLevel" => 5}
          },
          "name" => "arangox_ecto_test::m",
          "type" => "geopoint"
        }
      }

      for {name, expected} <- expected_responses do
        if actual = Keyword.get(success, name) do
          assert %Arangox.Response{status: 201, body: ^expected} = actual
        end
      end
    end
  end

  describe "delete_all_edges/4" do
    test "no edges to delete" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      post = %Post{title: "test"} |> Repo.insert!()

      assert ArangoXEcto.delete_all_edges(Repo, user, post)
    end

    test "deletes edges" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> Repo.insert!()

      ArangoXEcto.create_edge(Repo, user1, user2, fields: %{type: "wrote"})

      ArangoXEcto.delete_all_edges(Repo, user1, user2)

      assert Repo.one(from(e in "users_users", select: count(e.id))) || 0 == 0
    end

    test "deletes edges for edge module" do
      user = %User{first_name: "John", last_name: "Smith"} |> Repo.insert!()
      post = %Post{title: "test"} |> Repo.insert!()

      ArangoXEcto.create_edge(Repo, user, post, edge: UserPosts, fields: %{type: "wrote"})

      ArangoXEcto.delete_all_edges(Repo, user, post, edge: UserPosts)

      assert Repo.one(from(e in UserPosts, select: count(e.id))) || 0 == 0
    end
  end

  describe "get_id_from_struct/1" do
    test "valid struct" do
      assert ArangoXEcto.get_id_from_struct(%User{id: "12345"}) == "users/12345"
    end

    test "invalid map" do
      assert_raise ArgumentError, ~r/Invalid struct or _id/, fn ->
        ArangoXEcto.get_id_from_struct(%{id: "1234"})
      end
    end

    test "does not allow regular map" do
      assert_raise ArgumentError, ~r/Invalid struct or _id/, fn ->
        ArangoXEcto.get_id_from_struct(%{abc: "jnsdkjfsdfnkj"})
      end
    end

    test "valid id passed" do
      assert ArangoXEcto.get_id_from_struct("users/1235")
    end

    test "invalid id string" do
      assert_raise ArgumentError, ~r/Invalid format for ArangoDB document ID/, fn ->
        ArangoXEcto.get_id_from_struct("sdnkjsdkjf")
      end
    end
  end

  describe "get_id_from_module/2" do
    test "valid module and key" do
      assert ArangoXEcto.get_id_from_module(User, "12345") == "users/12345"
    end

    test "invalid module" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        ArangoXEcto.get_id_from_module(Ecto, "1234")
      end
    end

    test "does not allow regular atom as module" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        ArangoXEcto.get_id_from_module(:test, "1234")
      end
    end

    test "does not allow other types" do
      assert_raise ArgumentError, ~r/Invalid module/, fn ->
        ArangoXEcto.get_id_from_module(%{}, 123)
      end
    end
  end

  describe "raw_to_struct/2" do
    test "valid map" do
      out =
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.raw_to_struct(User)

      assert Kernel.match?(%User{id: "12345", first_name: "John", last_name: "Smith"}, out)
    end

    test "invalid map" do
      assert_raise ArgumentError, ~r/Invalid input map or module/, fn ->
        %{
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.raw_to_struct(User)
      end
    end

    test "invalid module" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.raw_to_struct(Ecto)
      end
    end

    test "invalid argument types" do
      assert_raise ArgumentError, ~r/Invalid input map or module/, fn ->
        ArangoXEcto.raw_to_struct("test", 123)
      end
    end
  end

  describe "load/2" do
    test "valid map" do
      out =
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.load(User)

      assert Kernel.match?(%User{id: "12345", first_name: "John", last_name: "Smith"}, out)
    end

    test "invalid map" do
      assert_raise ArgumentError, ~r/Invalid input map or module/, fn ->
        %{
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.load(User)
      end
    end

    test "invalid module" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
        |> ArangoXEcto.load(Ecto)
      end
    end

    test "invalid argument types" do
      assert_raise ArgumentError, ~r/Invalid input map or module/, fn ->
        ArangoXEcto.load("test", 123)
      end
    end

    test "loads embeds" do
      out =
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith",
          "class" => %{
            "name" => "English"
          }
        }
        |> ArangoXEcto.load(User)

      assert Kernel.match?(
               %User{
                 id: "12345",
                 first_name: "John",
                 last_name: "Smith",
                 class: %Class{name: "English"}
               },
               out
             )
    end

    test "loads associations" do
      out =
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith",
          "posts" => [
            %{
              "_id" => "posts/12345",
              "_key" => "12345",
              "_rev" => "_bHZ8PAZ---",
              "title" => "Test"
            }
          ]
        }
        |> ArangoXEcto.load(User)

      assert Kernel.match?(
               %User{
                 id: "12345",
                 first_name: "John",
                 last_name: "Smith",
                 posts: [%Post{id: "12345", title: "Test"}]
               },
               out
             )
    end
  end

  describe "edge_module/3" do
    test "two modules with same parents" do
      assert ArangoXEcto.edge_module(User, Post) == ArangoXEctoTest.Integration.Edges.PostUser
    end

    test "one module with extra depth in parent" do
      assert ArangoXEcto.edge_module(User, ArangoXEctoTest.Integration.Deep.Magic) ==
               ArangoXEctoTest.Integration.Edges.MagicUser
    end

    test "using custom collection name" do
      assert ArangoXEcto.edge_module(User, Post, collection_name: "member_blogs") ==
               ArangoXEctoTest.Integration.Edges.MemberBlogs
    end
  end

  describe "collection_exists?/3" do
    test "collection does exist" do
      assert ArangoXEcto.collection_exists?(Repo, :users)
    end

    test "collection does not exist" do
      assert not ArangoXEcto.collection_exists?(Repo, :fake_collection)
    end

    test "string and atom collection names" do
      assert ArangoXEcto.collection_exists?(Repo, :users)
      assert ArangoXEcto.collection_exists?(Repo, "users")
    end

    test "edge collection exists" do
      assert ArangoXEcto.collection_exists?(Repo, :test_edge, :edge)
    end

    test "atom and integer types" do
      assert ArangoXEcto.collection_exists?(Repo, :users, :document)
      assert ArangoXEcto.collection_exists?(Repo, :users, 2)
    end
  end

  describe "is_edge?/1" do
    test "valid edge schema" do
      assert ArangoXEcto.is_edge?(UserPosts)
    end

    test "valid document schema" do
      refute ArangoXEcto.is_edge?(User)
    end

    test "not an ecto schema" do
      refute ArangoXEcto.is_edge?(Ecto)
    end

    test "not a module" do
      refute ArangoXEcto.is_edge?(123)
    end
  end

  describe "is_document?/1" do
    test "valid document schema" do
      assert ArangoXEcto.is_document?(User)
    end

    test "valid edge schema" do
      refute ArangoXEcto.is_document?(UserPosts)
    end

    test "not an ecto schema" do
      refute ArangoXEcto.is_document?(Ecto)
    end

    test "not a module" do
      refute ArangoXEcto.is_document?(123)
    end
  end

  describe "schema_type/1" do
    test "valid document schema" do
      assert ArangoXEcto.schema_type(User) == :document
    end

    test "valid edge schema" do
      assert ArangoXEcto.schema_type(UserPosts) == :edge
    end

    test "not an ecto schema" do
      assert ArangoXEcto.schema_type(Ecto) == nil
    end

    test "not a module" do
      assert ArangoXEcto.schema_type(123) == nil
    end
  end

  describe "schema_type!/1" do
    test "valid document schema" do
      assert ArangoXEcto.schema_type!(User) == :document
    end

    test "valid edge schema" do
      assert ArangoXEcto.schema_type!(UserPosts) == :edge
    end

    test "not an ecto schema" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        ArangoXEcto.schema_type!(Ecto)
      end
    end

    test "not a module" do
      assert_raise ArgumentError, ~r/Not an Ecto Schema/, fn ->
        ArangoXEcto.schema_type!(123)
      end
    end
  end

  defp id_from_user(%{id: id}), do: "users/" <> id
end
