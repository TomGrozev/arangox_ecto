defmodule ArangoXEctoTest.Integration.RelationshipTest do
  use ArangoXEcto.Integration.Case,
    write: ["users", "posts", "comments", "posts_users", "user_content"]

  import CompileTimeAssertions

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

      %User{id: user_id, posts_two: [%Post{id: post_id}]} =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> Ecto.Changeset.cast_assoc(:posts_two, with: post_changeset)
        |> TestRepo.insert!()

      assert %User{id: ^user_id, posts_two: [%{title: "abc"}]} =
               TestRepo.get(User, user_id) |> TestRepo.preload(:posts_two)

      assert %Post{id: ^post_id, users_two: [%User{id: ^user_id}]} =
               TestRepo.get(Post, post_id) |> ArangoXEcto.preload(TestRepo, :users_two)
    end

    test "delete all assocs" do
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

      %User{posts_two: [post]} =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> Ecto.Changeset.cast_assoc(:posts_two, with: post_changeset)
        |> TestRepo.insert!()

      TestRepo.delete!(post)

      assert Enum.empty?(TestRepo.all(User))
      assert Enum.empty?(TestRepo.all(Post))
      assert Enum.empty?(TestRepo.all(UserPosts))
    end

    test "preload on graph connection" do
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

      assert %User{id: ^user_id, posts_two: [%Post{title: "abc"}]} =
               TestRepo.get(User, user_id) |> ArangoXEcto.preload(TestRepo, :posts_two)

      assert [%User{id: ^user_id, posts_two: [%Post{title: "abc"}]}] =
               [TestRepo.get(User, user_id)]
               |> ArangoXEcto.preload(TestRepo, :posts_two, timeout: 20_000)
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

    test "raises on invalid options supplied to graph relation" do
      assert_compile_time_raise(
        ArgumentError,
        "schema does not have the field :__id__ used by association",
        fn ->
          defmodule Test do
            use Ecto.Schema
            import ArangoXEcto.Schema, except: [schema: 2]
            import ArangoXEcto.Association

            schema "invalid_schema" do
              outgoing(:field, ArangoXEcto.Integration.User, on_delete: :invalid_option)
            end
          end
        end
      )

      assert_compile_time_raise(ArgumentError, "invalid `:on_delete` option for", fn ->
        defmodule Test do
          use ArangoXEcto.Schema

          schema "invalid_schema" do
            field :test, :string

            outgoing(:field, ArangoXEcto.Integration.User, on_delete: :invalid_option)
          end
        end
      end)

      assert_compile_time_raise(ArgumentError, "invalid `:on_replace` option for", fn ->
        defmodule Test do
          use ArangoXEcto.Schema

          schema "invalid_schema" do
            field :test, :string

            outgoing(:field, ArangoXEcto.Integration.User, on_replace: :invalid_option)
          end
        end
      end)

      assert_compile_time_raise(ArgumentError, "expected `:where` for", fn ->
        defmodule Test do
          use ArangoXEcto.Schema

          schema "invalid_schema" do
            field :test, :string

            outgoing(:field, ArangoXEcto.Integration.User, where: "invalid")
          end
        end
      end)

      assert_compile_time_raise(ArgumentError, "had a nil :edge value", fn ->
        defmodule Test do
          use ArangoXEcto.Schema

          schema "invalid_schema" do
            field :test, :string

            outgoing(:field, ArangoXEcto.Integration.User, edge: nil)
          end
        end
      end)

      assert_compile_time_raise(
        ArgumentError,
        "associations require the :edge option to be an atom",
        fn ->
          defmodule Test do
            use ArangoXEcto.Schema

            schema "invalid_schema" do
              field :test, :string

              outgoing(:field, ArangoXEcto.Integration.User, edge: "invalid")
            end
          end
        end
      )

      assert_compile_time_raise(
        ArgumentError,
        "invalid associated schemas defined in",
        fn ->
          defmodule Test do
            use ArangoXEcto.Schema

            schema "invalid_schema" do
              field :test, :string

              outgoing(:field, "invalid")
            end
          end
        end
      )

      assert_compile_time_raise(
        ArgumentError,
        "field/association :field already exists on schema",
        fn ->
          defmodule Test do
            use ArangoXEcto.Schema

            schema "invalid_schema" do
              field :test, :string

              outgoing(:field, ArangoXEcto.Integration.User)
              outgoing(:field, ArangoXEcto.Integration.User)
            end
          end
        end
      )

      assert_compile_time_raise(
        ArgumentError,
        "queryables must be a map with keys as schemas and value as a list of fields to be identified by",
        fn ->
          defmodule Test do
            use ArangoXEcto.Schema

            schema "invalid_schema" do
              field :test, :string

              outgoing(:field, %{
                ArangoXEcto.Integration.User => [:test],
                "invalid" => [:test]
              })
            end
          end
        end
      )
    end

    test "raises on invalid options supplied to edge" do
      assert_compile_time_raise(ArgumentError, "invalid `:on_replace` option for", fn ->
        defmodule Test do
          use ArangoXEcto.Edge,
            from: ArangoXEcto.Integration.User,
            to: ArangoXEcto.Integration.Post

          schema "invalid_edge" do
            edge_fields(on_replace: :invalid_option)
          end
        end
      end)

      assert_compile_time_raise(ArgumentError, "invalid option :where for edge_many/3", fn ->
        defmodule Test do
          use ArangoXEcto.Edge,
            from: ArangoXEcto.Integration.User,
            to: ArangoXEcto.Integration.Post

          schema "invalid_edge" do
            edge_fields(where: "invalid")
          end
        end
      end)

      assert_compile_time_raise(
        ArgumentError,
        "queryables must be a list of schemas or a map of modules and fields",
        fn ->
          defmodule Test do
            use ArangoXEcto.Edge,
              from: [ArangoXEcto.Integration.User, "invalid"],
              to: ArangoXEcto.Integration.Post

            schema "invalid_edge" do
              edge_fields()
            end
          end
        end
      )
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

  describe "cast_graph/3" do
    test "cast graph fails on schemaless changeset" do
      struct = %ArangoXEcto.Integration.Class{name: "some value"}

      assert_raise ArgumentError,
                   ~r"cast_graph/3 cannot be used to cast associations into embedded schemas or schemaless changesets",
                   fn ->
                     Ecto.Changeset.change(struct)
                     |> ArangoXEcto.Changeset.cast_graph(:name)
                   end
    end

    test "cast graph fails on non-cast changeset" do
      assert_raise ArgumentError,
                   ~r"cast_graph/3 expects the changeset to be cast",
                   fn ->
                     %Ecto.Changeset{data: nil}
                     |> ArangoXEcto.Changeset.cast_graph(:title)
                   end
    end

    test "cast graph with required field" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      post_changeset = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:title])
      end

      comment_changeset = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:text])
      end

      changeset =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.cast_graph(:my_content,
          with: %{
            Post => post_changeset,
            Comment => comment_changeset
          },
          required: true
        )

      assert [{:my_content, "can't be blank", [validation: :required]}] =
               changeset.errors
    end

    test "cast graph with no with supplied" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: "cba"},
          %{title: "abc"}
        ]
      }

      changeset =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.cast_graph(:my_content)

      [%{data: struct1}, %{data: struct2}] = Ecto.Changeset.get_change(changeset, :my_content)

      assert Comment == struct1.__struct__
      assert Post == struct2.__struct__
    end

    test "cast graph with no with and changeset function doesn't exists" do
      attrs = %{
        title: "My title",
        classes: [
          %{name: "My name"}
        ]
      }

      assert_raise ArgumentError,
                   ~r"the module ArangoXEcto.Integration.Class does not define a changeset/2 function",
                   fn ->
                     Ecto.Changeset.cast(%Post{}, attrs, [:title])
                     |> ArangoXEcto.Changeset.cast_graph(:classes)
                   end
    end

    test "cast graph with function changeset" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: 123}
        ]
      }

      changeset_fun = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:text])
      end

      assert %{changes: %{my_content: [_]}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.cast_graph(:my_content, with: changeset_fun)
    end

    test "cast graph with nil changeset option" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: 123}
        ]
      }

      assert_raise ArgumentError,
                   ~r"the function for module ArangoXEcto.Integration.Comment is not a valid function",
                   fn ->
                     Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
                     |> ArangoXEcto.Changeset.cast_graph(:my_content,
                       with: %{
                         Comment => nil
                       }
                     )
                   end
    end

    test "cast graph with module that doesn't exist in relation" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: 123}
        ]
      }

      changeset_fun = fn struct, map ->
        Ecto.Changeset.cast(struct, map, [:text])
      end

      assert_raise ArgumentError,
                   ~r"the module ArangoXEcto.Integration.User is not a valid related schema for this association",
                   fn ->
                     Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
                     |> ArangoXEcto.Changeset.cast_graph(:my_content,
                       with: %{
                         User => changeset_fun
                       }
                     )
                   end
    end

    test "cast graph with invalid with parameter" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          %{text: 123}
        ]
      }

      assert_raise ArgumentError,
                   ~r"the with clause is not valid",
                   fn ->
                     Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
                     |> ArangoXEcto.Changeset.cast_graph(:my_content,
                       with: "invalid"
                     )
                   end
    end

    test "cast graph with invalid value fails" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_content: [
          "invalid"
        ]
      }

      assert %{errors: [my_content: {"is invalid", [validation: :assoc, type: {:array, :map}]}]} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.cast_graph(:my_content)
    end

    test "cast graph with module as mapping" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_posts: [
          %{title: "some title"}
        ]
      }

      assert %{changes: %{my_posts: [_]}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.cast_graph(:my_posts)
    end

    test "cast graph update struct" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        my_posts: [
          %{title: "some title"}
        ]
      }

      user =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.cast_graph(:my_posts)
        |> TestRepo.insert!()

      assert %{
               changes: %{
                 my_posts: [%{action: :replace}, %{changes: %{title: "some other title"}}]
               }
             } =
               Ecto.Changeset.cast(user, %{my_posts: [%{title: "some other title"}]}, [])
               |> ArangoXEcto.Changeset.cast_graph(:my_posts)
    end
  end

  describe "put_graph/4" do
    test "can put a value into changeset" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      post = %Post{title: "Some title"}

      assert %{changes: %{my_content: [%{data: %Post{}}]}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_content, [post])
    end

    test "no types set in changeset" do
      post = %Post{title: "Some title"}

      assert_raise ArgumentError,
                   ~r"changeset does not have types information",
                   fn ->
                     Ecto.Changeset.cast(%User{}, %{}, [])
                     |> Map.put(:types, nil)
                     |> ArangoXEcto.Changeset.put_graph(:my_content, [post])
                   end
    end

    test "on replace mark as invalid" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      user =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.put_graph(:my_comments, [%Comment{text: "Some text"}])
        |> TestRepo.insert!()

      assert %{errors: [my_comments: {"is invalid", [type: {:array, :map}]}]} =
               Ecto.Changeset.cast(user, %{first_name: "Robert"}, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [%Comment{text: "Some
        other text"}])
    end

    test "on replace raises" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      user =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.put_graph(:my_content, [%Comment{text: "Some text"}])
        |> TestRepo.insert!()

      assert_raise RuntimeError,
                   ~r"you are attempting to change graph relation :my_content of",
                   fn ->
                     Ecto.Changeset.cast(user, %{first_name: "Robert"}, [:first_name, :last_name])
                     |> ArangoXEcto.Changeset.put_graph(:my_content, [%Comment{text: "Some
        other text"}])
                   end
    end

    test "changes cleared on no difference" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      user =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.put_graph(:my_comments, [%Comment{text: "Some text"}])
        |> TestRepo.insert!()

      assert %{valid?: true, changes: %{first_name: "Robert"} = changes} =
               Ecto.Changeset.cast(user, %{first_name: "Robert"}, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(
                 :my_comments,
                 user.my_comments
               )

      refute Map.has_key?(changes, :my_comments)
    end

    test "raises on trying to insert wrong type" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      assert_raise RuntimeError,
                   ~r"expected changeset data to be one of",
                   fn ->
                     Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
                     |> ArangoXEcto.Changeset.put_graph(:my_content, [%User{first_name: "Ben"}])
                   end
    end

    test "put changeset in graph" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      changeset = %Comment{text: "Some text"} |> Ecto.Changeset.change()

      assert %{changes: %{my_comments: [%{data: %Comment{}}]}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [changeset])

      assert %{changes: %{my_comments: [%{data: %Comment{}}]}} =
               Ecto.Changeset.cast(%User{my_comments: nil}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [changeset])

      assert %{changes: changes} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [
                 Map.put(changeset, :action, :ignore)
               ])

      refute Map.has_key?(changes, :my_comments)
    end

    test "update changeset in graph" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      changeset = %Comment{text: "Some text"} |> Ecto.Changeset.change()

      %User{my_comments: [comment]} =
        user =
        Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
        |> ArangoXEcto.Changeset.put_graph(:my_comments, [changeset])
        |> TestRepo.insert!()

      comment_keyword = [id: comment.id, text: "Some other text"]
      comment = Ecto.Changeset.change(comment, %{text: "Some other text"})

      assert %{changes: %{my_comments: [%{changes: %{text: "Some other text"}}]}} =
               Ecto.Changeset.cast(user, %{first_name: "Robert"}, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [comment])

      assert %{changes: %{my_comments: [%{changes: %{text: "Some other text"}}]}} =
               Ecto.Changeset.cast(user, %{first_name: "Robert"}, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(
                 :my_comments,
                 [comment_keyword]
               )
    end

    test "put empty value" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      assert %{changes: %{my_comments: []}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [])
    end

    test "put invalid value type" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      assert %{errors: [my_comments: {"is invalid", [type: {:array, :map}]}]} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, "invalid")
    end

    test "put with nil existing value" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      assert %{changes: %{my_comments: [%{data: %Comment{}}]}} =
               Ecto.Changeset.cast(%User{my_comments: nil}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [%Comment{text: "Some
        other text"}])
    end

    test "can't put more than once on unique field" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      comment = %Comment{text: "Some other text"} |> TestRepo.insert!()

      assert %{
               changes: %{
                 my_comments: [%{valid?: true}, %{errors: [id: {"has already been taken", []}]}]
               }
             } =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_comments, [comment, comment])
    end

    test "can put more than once on regular field" do
      attrs = %{
        first_name: "John",
        last_name: "Smith"
      }

      comment = %Comment{text: "Some other text"} |> TestRepo.insert!()

      assert %{changes: %{my_content: [%{valid?: true}, %{valid?: true}]}} =
               Ecto.Changeset.cast(%User{}, attrs, [:first_name, :last_name])
               |> ArangoXEcto.Changeset.put_graph(:my_content, [comment, comment])
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
