defmodule ArangoXEcto.Schema do
  @moduledoc """
  This module is a helper to automatically specify the primary key.

  The primary key is the Arango `_key` field but the _id field is also provided.

  Schema modules should use this module by add `use ArangoXEcto.Schema` to the module. The only
  exception to this is if the collection is an edge collection, in that case refer to ArangoXEcto.Edge.

  ## Example

      defmodule MyProject.Accounts.User do
        use ArangoXEcto.Schema
        import Ecto.Changeset

        schema "users" do
          field :first_name, :string
          field :last_name, :string

          timestamps()
        end

        @doc false
        def changeset(app, attrs) do
          app
          |> cast(attrs, [:first_name, :last_name])
          |> validate_required([:first_name, :last_name])
        end
      end
  """
  require Ecto.Schema

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      import Ecto.Schema, only: [embedded_schema: 1]

      @primary_key {:id, :binary_id, autogenerate: true, source: :_key}
      @timestamps_opts []
      @foreign_key_type :binary_id
      @schema_prefix nil
      @schema_context nil
      @field_source_mapper fn x -> x end

      Module.register_attribute(__MODULE__, :ecto_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_virtual_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_query_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_field_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_embeds, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_raw, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autogenerate, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autoupdate, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_redact_fields, accumulate: true)
      Module.put_attribute(__MODULE__, :ecto_derive_inspect_for_redacted_fields, true)
      Module.put_attribute(__MODULE__, :ecto_autogenerate_id, nil)

      def __collection_options__, do: []
      def __collection_indexes__, do: []

      defoverridable __collection_options__: 0, __collection_indexes__: 0
    end
  end

  @doc """
  A wrapper around the `Ecto.Schema.schema/2` to add the _id field
  """
  defmacro schema(source, do: {:__block__, _, args}) do
    block =
      {:__block__, [],
       [{:field, [], [:__id__, :binary_id, [source: :_id, read_after_writes: true]]} | args]}

    quote do
      Ecto.Schema.schema(unquote(source), do: unquote(block))
    end
  end

  defmacro schema(source, do: block) do
    quote do
      Ecto.Schema.schema(unquote(source), do: unquote(block))
    end
  end

  @doc """
  Defines collection options for dynamic creation

  When using dynamic mode for collection creation you may want to add options for when the collection is created.
  To add options that will be applied you pass them to as a keyword list.

  The available options can be found in the `ArangoXEcto.Migration.Collection` module. These options also work in edge collections.

  ## Example

  To specify a UUID as the collection key type you just supply it as the key option type.

      options [
        keyOptions: %{type: :uuid}
      ]
  """
  defmacro options(options) do
    quote do
      def __collection_options__, do: unquote(options)
    end
  end

  @doc """
  Defines indexs for collection dynamic creation

  The available options can be found in the `ArangoXEcto.Migration.Index` module.

  ## Example

  To create a generic hash index you don't need to pass the type.

      indexes [
        [fields: [:email, :username]]
      ]

  To create a geoJson index set the type to geo and set `geoJson` to true.

      indexes [
        [fields: [:point], type: :geo, geoJson: true]
      ]

  To create a two seperate indexes just supply them seperately.

      indexes [
        [fields: [:email]],
        [fields: [:username]]
      ]
  """
  defmacro indexes(indexes) do
    quote do
      def __collection_indexes__, do: unquote(indexes)
    end
  end

  @doc """
  Defines an outgoing relationship of many objects

  Behind the scenes this defines a many to many relationship so that Ecto can load the relationship using the built
  in functions.

  The use of this function **MUST** be accompanied by a `incoming/3` definition in the other target node.

  This will also define the `__id__` field if it is not already defined so that ecto can map the relationship.

  ## Example

      defmodule MyProject.User do
        use ArangoXEcto.Schema

        schema "users" do
          field :name, :string

          # Will use the automatically generated edge
          outgoing :posts, MyProject.Post

          # Will use the UserPosts edge
          outgoing :posts, MyProject.Post, edge: MyProject.UserPosts
        end
      end
  """
  defmacro outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      many_to_many(unquote(name), unquote(target),
        join_through:
          Keyword.get(opts, :edge, ArangoXEcto.edge_module(__MODULE__, unquote(target))),
        join_keys: [_from: :__id__, _to: :__id__],
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an outgoing relationship of one object

  Unlike `outgoing/3`, this does not create a graph relation and instead places the `_id` in a field in the incoming
  schema. This **MUST** be accompanied by a `one_incoming/3` definition in the other target schema.

  Behind the scenes this injects the `__id__` field to store the `_id` value and uses the built-in Ecto `has_one/3`
  function.

  Options passed to the `opts` attribute are passed to the `has_many/3` definition. Refrain from overriding the
  `:references` and `:foreign_key` attributes unless you know what you are doing.

  ## Example

      defmodule MyProject.User do
        use ArangoXEcto.Schema

        schema "users" do
          field :name, :string

          one_outgoing :best_post, MyProject.Post
        end
      end
  """
  defmacro one_outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      has_one(unquote(name), unquote(target),
        references: :__id__,
        foreign_key: Ecto.Association.association_key(__MODULE__, "id"),
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an incoming relationship

  Behind the scenes this defines a many to many relationship so that Ecto can load the relationship using the built
  in functions.

  The use of this function **MUST** be accompanied by a `outgoing/3` definition in the other target node.

  This will also define the `__id__` field if it is not already defined so that ecto can map the relationship.

  ## Example

      defmodule MyProject.Post do
        use ArangoXEcto.Schema

        schema "posts" do
          field :title, :string

          # Will use the automatically generated edge
          incoming :users, MyProject.User

          # Will use the UserPosts edge
          incoming :users, MyProject.User, edge: MyProject.UserPosts
        end
      end
  """
  defmacro incoming(name, source, opts \\ []) do
    quote do
      opts = unquote(opts)

      many_to_many(unquote(name), unquote(source),
        join_through:
          Keyword.get(
            opts,
            :edge,
            ArangoXEcto.edge_module(__MODULE__, unquote(source), create: false)
          ),
        join_keys: [_to: :__id__, _from: :__id__],
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an incoming relationship of one object

  Unlike `incoming/3`, this does not create a graph relation and instead places the `_id` in a field. If the value
  passed to the name attribute is `:user` then the foreign key created on this schema will be `:user_id` and will
  store the full `_id` of that user. By storing the full `_id`, you are still able to perform full AQL queries.

  This **MUST** be accompanied by a `one_outgoing/3` definition in the other target schema.

  Behind the scenes this injects the `__id__` field to store the `_id` value and uses the built-in Ecto `belongs_to/3`
  function.

  Options passed to the `opts` attribute are passed to the `belongs_to/3` definition. Refrain from overriding the
  `:references` and `:foreign_key` attributes unless you know what you are doing.

  ## Example

      defmodule MyProject.Post do
        use ArangoXEcto.Schema

        schema "posts" do
          field :title, :string

          one_incoming :user, MyProject.User
        end
      end
  """
  defmacro one_incoming(name, source, opts \\ []) do
    quote do
      opts = unquote(opts)

      belongs_to(unquote(name), unquote(source),
        references: :__id__,
        foreign_key: unquote(name) |> build_foreign_key(),
        on_replace: :delete
      )
    end
  end

  @doc """
  Creates a foreign key with correct format

  Appends _id to the atom
  """
  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_id")
    |> String.to_atom()
  end
end
