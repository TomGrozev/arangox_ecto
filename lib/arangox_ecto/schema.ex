defmodule ArangoXEcto.Schema do
  @moduledoc """
  An ArangoDB specific implementation of the `Ecto.Schema` module.

  The primary key is the Arango `_key` field and is mapped to `:id`. The `_id` field is also 
  provided in the `:__id__` field. The `:__id__` field is primarily used for graph associations but
  is available in all structs.

  Schema modules should use this module by adding `use ArangoXEcto.Schema` to the module. The only
  exception to this is if the collection is an edge collection, in that case refer to 
  `ArangoXEcto.Edge`.

  This module works, for the most part, the same as the `Ecto.Schema` module. Where the two modules
  differ is that this module sets the primary key and adds the `:__id__` field, as described above.
  In addition, additional functionality for ArangoDB is available, such as `outgoing` and `incoming`
  relations and collection indexes & options.

  ## Example

      defmodule MyProject.Accounts.User do
        use ArangoXEcto.Schema
        import Ecto.Changeset

        schema "users" do
          field :first_name, :string
          field :last_name, :string

          outgoing :posts, Post

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
      import ArangoXEcto.Association

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
  Defines an ArangoDB schema.

  A wrapper around the `Ecto.Schema.schema/2` to add the `:__id__` field. For more info, see the
  docs for `Ecto.Schema.schema/2`.
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

  When using dynamic mode for collection creation this will add options for when the collection is 
  created. If in static mode, this will simply be ignored.

  This accepts a keyword list of options. The available options can be found in the 
  `ArangoXEcto.Migration.Collection` module.

  This function also works in edge collections.

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
  Defines indexes for collection dynamic creation

  When using dynamic mode for collection creation this will add indexes after the collection is 
  created. If in static mode, this will simply be ignored.

  This accepts a list of keyword lists that are the indexes. The available options can be found in 
  the `ArangoXEcto.Migration.Index` module. 

  This function also works in edge collections.

  ## Example

  To create a generic hash index you don't need to pass the type.

      indexes [
        [fields: [:email, :username]]
      ]

  To create a geoJson index set the type to geo and set `geoJson` to true.

      indexes [
        [fields: [:point], type: :geo, geoJson: true]
      ]

  To create a two separate indexes just supply them separately.

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
  Defines an outgoing relationship to many objects

  While not strictly required, you can add an `incoming/3` definition in the other target node so
  that the reverse can be queried also.

  If in static mode you still have to have a migration, even for the dynamically generated edges.
  You can use the rules of how edges are named from `ArangoXEcto.edge_module/3` for the name of the
  edge or if you want to be explicit (and it often is good practice to do so) you can create an edge
  module and pass the edge.

  ## Parameters

    * `name` - The name of the relation
    * `target` - The target of the relation, can either be another schema or a mapper (see below for
                more info)
    * `opts` - See below

  ## Options

    * `:edge` - The edge schema to use, default will generate a new edge
    * `:on_replace` - The action taken on the association when the record is
                      replaced when casting or manipulating the parent changeset.
    * `:where` - A filter for the association. See "Filtering associations" in 
                `Ecto.Schema.has_many/3`.

  ## Mapping a target

  In ArangoDB you can have multiple different types of collections related through an edge. To 
  represent this we use a map to represent the target. The keys of the map is the schema that we
  want to use and the value is a list of field names. When Ecto maps a result to a struct it will
  use the list of fields to determine which schema to use. If any of the fields in the list are 
  present then that schema will be chosen. If two match, then the first will be selected.

      outgoing :content, %{
        MyProject.Post => [:title],
        MyProject.Comment => [:text]
      }, edge: MyProject.Content

  You can specify an `incoming/3` relationship in, for example, the `MyProject.Post` and the
  `MyProject.Comment` schemas seperatley. The only requirement would be to ensure the same edge is
  used.

  The edge definition would look something like the following. Take note of the list supplied for
  the `:to` option.

      defmodule MyProject.Content do
        use ArangoXEcto.Edge,
          from: MyProject.User,
          to: [MyProject.Post, MyProject.Comment]

        schema "content" do
          edge_fields()
        end
      end

  ## Example

      defmodule MyProject.User do
        use ArangoXEcto.Schema

        schema "users" do
          field :name, :string

          # Will use the automatically generated edge
          outgoing :posts, MyProject.Post

          # Will use the UserPosts edge
          outgoing :posts, MyProject.Post, edge: MyProject.UserPosts

          # Creates a multi relation
          outgoing :content, %{
            MyProject.Post => [:title],
            MyProject.Comment => [:text]
          }, edge: MyProject.Content
        end
      end
  """
  defmacro outgoing(name, target, opts \\ []) do
    quote do
      graph(unquote(name), unquote(target), :outbound, unquote(opts))
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
  # TODO: remove this
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

  This is almost exactly the same as `outgoing/3` except it defines that the relationship is
  incoming. This means that on the edge the from and to order is swapped. It will work exactly the
  same if you used an `incoming/3` or an `outgoing/3`.

  One thing to keep in mind is that this function will not automaticallly define an edge module
  and will require an `outbound/3` definition. This doesn't matter when supplying an edge schema as
  the options.

  For more information and available options see `outgoing/3`.

  ## Example

      defmodule MyProject.Post do
        use ArangoXEcto.Schema

        schema "posts" do
          field :title, :string

          # Will use the automatically generated edge
          incoming :users, MyProject.User

          # Will use the UserPosts edge
          incoming :users, MyProject.User, edge: MyProject.UserPosts

          # Creates a multi relation
          incoming :entities, %{
            MyProject.User => [:first_name],
            MyProject.Company => [:name]
          }, edge: MyProject.Entities
        end
      end

  For the multi relation example, the following could be the edge definition.

      defmodule MyProject.Entities do
        use ArangoXEcto.Edge,
          from: [MyProject.User, MyProject.Company],
          to: MyProject.Post

        schema "entities" do
          edge_fields()
        end
      end
  """
  defmacro incoming(name, source, opts \\ []) do
    quote do
      graph(unquote(name), unquote(source), :inbound, unquote(opts))
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
  # TODO: remove this
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
  # TODO: remove this
  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_id")
    |> String.to_atom()
  end
end
