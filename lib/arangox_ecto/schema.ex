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

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import unquote(__MODULE__)

      @primary_key {:id, :binary_id, autogenerate: true, source: :_key}
      @foreign_key_type :binary_id
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
          many_outgoing :posts, MyProject.Post

          # Will use the UserPosts edge
          many_outgoing :posts, MyProject.Post, edge: MyProject.UserPosts
        end
      end
  """
  defmacro many_outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      try do
        field(:__id__, :binary_id, source: :_id, read_after_writes: true)
      rescue
        ArgumentError -> :ok
      end

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
  """
  # TODO: Setup only one outgoing
  defmacro one_outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      has_one(unquote(name), unquote(target),
        foreign_key: unquote(name) |> build_foreign_key(),
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an incoming relationship

  Behind the scenes this defines a many to many relationship so that Ecto can load the relationship using the built
  in functions.

  The use of this function **MUST** be accompanied by a `many_outgoing/3` or `one_outgoing/3` definition in the
  other target node.

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

      try do
        field(:__id__, :binary_id, source: :_id, read_after_writes: true)
      rescue
        ArgumentError -> :ok
      end

      many_to_many(unquote(name), unquote(source),
        join_through:
          Keyword.get(opts, :edge, ArangoXEcto.edge_module(__MODULE__, unquote(source))),
        join_keys: [_to: :__id__, _from: :__id__],
        on_replace: :delete
      )
    end
  end

  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_id")
    |> String.to_atom()
  end
end
