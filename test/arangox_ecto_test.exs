defmodule ArangoXEctoTest do
  use ArangoXEcto.Integration.Case,
    write: ["users", "posts", "posts_users", "posts_users_options", "user_user"]

  alias ArangoXEcto.Integration.{Class, Post, User, UserPosts, UserPostsOptions}
  alias ArangoXEcto.Integration.{DynamicRepo, TestRepo}

  import Ecto.Query

  describe "aql_query/4 and aql_query!/4" do
    @describetag :integration

    test "invalid AQL query" do
      query = "FOsdfsdfgdfs abc"

      {:error, %Arangox.Error{error_num: 1501}} = ArangoXEcto.aql_query(TestRepo, query)

      assert_raise Arangox.Error, ~r/\[400\] \[1501\] AQL: syntax error/i, fn ->
        ArangoXEcto.aql_query!(TestRepo, query)
      end
    end

    test "non existent collection AQL query" do
      query = "FOR var in non_existent RETURN var"

      {:error, %Arangox.Error{error_num: 1203}} = ArangoXEcto.aql_query(TestRepo, query)

      assert_raise Arangox.Error, ~r/\[404\] \[1203\] AQL: collection or view not found/, fn ->
        ArangoXEcto.aql_query!(TestRepo, query)
      end
    end

    test "filter AQL query" do
      # A fix for something weird in the CI pipeline
      TestRepo.delete_all(User)
      fname = "John"
      lname = "Smith"
      %User{first_name: fname, last_name: lname} |> TestRepo.insert!()

      collection_name = User.__schema__(:source)

      query = """
      FOR var in @@collection_name
      FILTER var.first_name == @fname AND var.last_name == @lname
      RETURN var
      """

      assert {:ok,
              {1,
               [
                 %{
                   "_id" => _,
                   "_key" => _,
                   "_rev" => _,
                   "first_name" => ^fname,
                   "last_name" => ^lname
                 }
               ]}} =
               ArangoXEcto.aql_query(TestRepo, query, [
                 {:"@collection_name", collection_name},
                 fname: fname,
                 lname: lname
               ])

      assert {1,
              [
                %{
                  "_id" => _,
                  "_key" => _,
                  "_rev" => _,
                  "first_name" => ^fname,
                  "last_name" => ^lname
                }
              ]} =
               ArangoXEcto.aql_query!(TestRepo, query, [
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

      assert {:ok, {0, []}} =
               ArangoXEcto.aql_query(
                 TestRepo,
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
      assert_raise ArgumentError,
                   "Invalid function [non_existent] passed to `Arangox` module",
                   fn ->
                     ArangoXEcto.api_query(TestRepo, :non_existent, "/_api/collections")
                   end
    end

    test "valid function but not allowed" do
      assert_raise ArgumentError,
                   ~r/Invalid function \[start_link\] passed to `Arangox` module/,
                   fn ->
                     ArangoXEcto.api_query(TestRepo, :start_link, "")
                   end
    end

    test "valid Arangox function" do
      assert {:ok, %Arangox.Response{body: %{"version" => _, "error" => _, "code" => _}}} =
               ArangoXEcto.api_query(TestRepo, :get, "/_admin/database/target-version")
    end
  end

  describe "create_edge/4" do
    test "create edge with no fields and no custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> TestRepo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(TestRepo, user1, user2)

      assert %{_from: ^from, _to: ^to} = edge
    end

    test "create edge with no fields and a custom name" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> TestRepo.insert!()

      from = id_from_user(user1)
      to = id_from_user(user2)

      edge = ArangoXEcto.create_edge(TestRepo, user1, user2, collection_name: "posts_users")

      assert %{_from: ^from, _to: ^to} = edge
    end

    test "create edge with fields and a custom module" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      post = %Post{title: "abc"} |> TestRepo.insert!()

      from = "posts/" <> post.id
      to = id_from_user(user)

      edge =
        ArangoXEcto.create_edge(TestRepo, post, user, edge: UserPosts, fields: %{type: "wrote"})

      assert %UserPosts{_from: ^from, _to: ^to, type: "wrote"} = edge
    end

    test "create edge with options and indexes" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      post = %Post{title: "abc"} |> TestRepo.insert!()

      from = "posts/" <> post.id
      to = id_from_user(user)

      edge =
        ArangoXEcto.create_edge(TestRepo, post, user,
          edge: UserPostsOptions,
          fields: %{type: "wrote"}
        )

      assert %UserPostsOptions{_from: ^from, _to: ^to, type: "wrote"} = edge

      assert {:ok,
              %Arangox.Response{
                body: %{"indexes" => [_, _, %{"fields" => ["type"], "unique" => true}]}
              }} =
               ArangoXEcto.api_query(TestRepo, :get, "/_api/index?collection=posts_users_options")

      assert {:ok,
              %Arangox.Response{
                body: %{"keyOptions" => %{"type" => "uuid"}}
              }} =
               ArangoXEcto.api_query(
                 TestRepo,
                 :get,
                 "/_api/collection/posts_users_options/properties"
               )
    end
  end

  describe "create_view/2" do
    test "creates a new view but fails on recreate" do
      assert :ok = ArangoXEcto.create_view(DynamicRepo, ArangoXEcto.Integration.UsersView)

      assert {:error, "duplicate name"} =
               ArangoXEcto.create_view(DynamicRepo, ArangoXEcto.Integration.UsersView)
    end

    test "automatically creates collection if it doesn't exist" do
      # Comments collection doesn't exist by default
      assert :ok = ArangoXEcto.create_view(DynamicRepo, ArangoXEcto.Integration.CommentView)
    end

    test "error on invalid view schema" do
      # Not a view schema
      assert_raise ArgumentError, ~r/not a valid view schema/, fn ->
        ArangoXEcto.create_view(DynamicRepo, ArangoXEcto)
      end
    end

    test "automatically creates analyzers in dynamic mode" do
      assert :ok = ArangoXEcto.create_view(DynamicRepo, ArangoXEcto.Integration.AnalyzerTestView)
    end
  end

  describe "create_analyzers/2" do
    test "creates analyzers" do
      # Fix for ArangoDB versions legacy parameter
      {:ok, %Arangox.Response{body: %{"version" => version}}} =
        ArangoXEcto.api_query(DynamicRepo, :get, "/_api/version")

      analyzer_l =
        if Version.compare(version, "3.10.5") == :lt do
          %{
            "features" => ["norm"],
            "properties" => %{
              "options" => %{"maxCells" => 21, "maxLevel" => 24, "minLevel" => 5},
              "type" => "shape"
            },
            "name" => "arangox_ecto_dynamic_test::l",
            "type" => "geojson"
          }
        else
          %{
            "features" => ["norm"],
            "properties" => %{
              "options" => %{"maxCells" => 21, "maxLevel" => 24, "minLevel" => 5},
              "type" => "shape",
              "legacy" => false
            },
            "name" => "arangox_ecto_dynamic_test::l",
            "type" => "geojson"
          }
        end

      expected_responses = [
        %{
          "features" => ["norm"],
          "properties" => %{},
          "name" => "arangox_ecto_dynamic_test::a",
          "type" => "identity"
        },
        %{
          "features" => ["frequency", "position"],
          "properties" => %{"delimiter" => ","},
          "name" => "arangox_ecto_dynamic_test::b",
          "type" => "delimiter"
        },
        %{
          "features" => ["frequency", "position", "norm"],
          "properties" => %{"locale" => "en"},
          "name" => "arangox_ecto_dynamic_test::c",
          "type" => "stem"
        },
        %{
          "features" => ["frequency", "position"],
          "properties" => %{"accent" => false, "case" => "lower", "locale" => "en"},
          "name" => "arangox_ecto_dynamic_test::d",
          "type" => "norm"
        },
        %{
          "features" => [],
          "properties" => %{
            "endMarker" => "b",
            "max" => 5,
            "min" => 3,
            "preserveOriginal" => true,
            "startMarker" => "a",
            "streamType" => "binary"
          },
          "name" => "arangox_ecto_dynamic_test::e",
          "type" => "ngram"
        },
        %{
          "features" => ["frequency", "norm"],
          "properties" => %{
            "accent" => false,
            "case" => "lower",
            "edgeNgram" => %{"min" => 3},
            "locale" => "en",
            "stemming" => false,
            "stopwords" => ["abc"]
          },
          "name" => "arangox_ecto_dynamic_test::f",
          "type" => "text"
        },
        %{
          "features" => ["frequency"],
          "properties" => %{"locale" => "en"},
          "name" => "arangox_ecto_dynamic_test::g",
          "type" => "collation"
        },
        %{
          "features" => ["norm"],
          "properties" => %{
            "batchSize" => 500,
            "collapsePositions" => true,
            "keepNull" => false,
            "memoryLimit" => 2_097_152,
            "queryString" => "RETURN SOUNDEX(@param)",
            "returnType" => "string"
          },
          "name" => "arangox_ecto_dynamic_test::h",
          "type" => "aql"
        },
        %{
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
          "name" => "arangox_ecto_dynamic_test::i",
          "type" => "pipeline"
        },
        %{
          "features" => [],
          "properties" => %{"hex" => false, "stopwords" => ["xyz"]},
          "name" => "arangox_ecto_dynamic_test::j",
          "type" => "stopwords"
        },
        %{
          "features" => [],
          "properties" => %{"break" => "all", "case" => "none"},
          "name" => "arangox_ecto_dynamic_test::k",
          "type" => "segmentation"
        },
        analyzer_l,
        %{
          "features" => ["norm"],
          "properties" => %{
            "latitude" => ["lat", "latitude"],
            "longitude" => ["long", "longitude"],
            "options" => %{"maxCells" => 21, "maxLevel" => 24, "minLevel" => 5}
          },
          "name" => "arangox_ecto_dynamic_test::m",
          "type" => "geopoint"
        }
      ]

      assert :ok = ArangoXEcto.create_analyzers(DynamicRepo, ArangoXEcto.Integration.Analyzers)

      {:ok, %Arangox.Response{body: %{"result" => analyzers}}} =
        ArangoXEcto.api_query(DynamicRepo, :get, "/_api/analyzer")

      for %{"name" => expected_name} = expected <- expected_responses do
        actual = Enum.find(analyzers, fn %{"name" => name} -> name == expected_name end)
        assert ^expected = actual
      end
    end
  end

  describe "delete_all_edges/4" do
    test "no edges to delete" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      post = %Post{title: "test"} |> TestRepo.insert!()

      assert ArangoXEcto.delete_all_edges(TestRepo, user, post)
    end

    test "deletes edges" do
      user1 = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      user2 = %User{first_name: "Jane", last_name: "Doe"} |> TestRepo.insert!()

      ArangoXEcto.create_edge(TestRepo, user1, user2, fields: %{type: "wrote"})

      ArangoXEcto.delete_all_edges(TestRepo, user1, user2)

      assert TestRepo.one(from(e in "user_user", select: count(e.id))) || 0 == 0
    end

    test "deletes edges for edge module" do
      user = %User{first_name: "John", last_name: "Smith"} |> TestRepo.insert!()
      post = %Post{title: "test"} |> TestRepo.insert!()

      ArangoXEcto.create_edge(TestRepo, post, user, edge: UserPosts, fields: %{type: "wrote"})

      ArangoXEcto.delete_all_edges(TestRepo, post, user, edge: UserPosts)

      assert TestRepo.one(from(e in UserPosts, select: count(e.id))) || 0 == 0
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
      assert ArangoXEcto.edge_module(User, Post) == ArangoXEcto.Integration.Edges.PostUser
    end

    test "one module with extra depth in parent" do
      assert ArangoXEcto.edge_module(User, ArangoXEcto.Integration.Deep.Magic) ==
               ArangoXEcto.Integration.Edges.MagicUser
    end

    test "multiple modules with depth" do
      assert ArangoXEcto.edge_module([User, Post], ArangoXEcto.Integration.Deep.Magic) ==
               ArangoXEcto.Integration.Edges.MagicPostUser
    end

    test "using custom collection name" do
      assert ArangoXEcto.edge_module(User, Post, collection_name: "member_blogs") ==
               ArangoXEcto.Integration.Edges.MemberBlogs
    end
  end

  describe "collection_exists?/3" do
    test "collection does exist" do
      assert ArangoXEcto.collection_exists?(TestRepo, :users)
    end

    test "collection does not exist" do
      assert not ArangoXEcto.collection_exists?(TestRepo, :fake_collection)
    end

    test "string and atom collection names" do
      assert ArangoXEcto.collection_exists?(TestRepo, :users)
      assert ArangoXEcto.collection_exists?(TestRepo, "users")
    end

    test "edge collection exists" do
      assert ArangoXEcto.collection_exists?(TestRepo, :posts_users, :edge)
    end

    test "atom and integer types" do
      assert ArangoXEcto.collection_exists?(TestRepo, :users, :document)
      assert ArangoXEcto.collection_exists?(TestRepo, :users, 2)
    end
  end

  describe "is_edge?/1" do
    test "valid edge schema" do
      assert ArangoXEcto.edge?(UserPosts)
    end

    test "valid document schema" do
      refute ArangoXEcto.edge?(User)
    end

    test "not an ecto schema" do
      refute ArangoXEcto.edge?(Ecto)
    end

    test "not a module" do
      refute ArangoXEcto.edge?(123)
    end
  end

  describe "is_document?/1" do
    test "valid document schema" do
      assert ArangoXEcto.document?(User)
    end

    test "valid edge schema" do
      refute ArangoXEcto.document?(UserPosts)
    end

    test "not an ecto schema" do
      refute ArangoXEcto.document?(Ecto)
    end

    test "not a module" do
      refute ArangoXEcto.document?(123)
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
