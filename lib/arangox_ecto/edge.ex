defmodule ArangoXEcto.Edge do
  @moduledoc """
  Defines an Arango Edge collection as an Ecto Schema Module.

  This will define the required fields of an edge (`_from` and `_to`) and will define the default changeset.

  Edge modules are dynamically created in the environment if they don't already exist. For more on 
  how edge modules are dynamically generated, please read `ArangoXEcto.edge_module/3`.

  Edges utilise Ecto relationships so that the powerful Ecto features can be used. Each Node 
  requires a relationship to be set, either a `outgoing/3` or `incoming/3`. Behind the scenes this 
  creates a relationship similar to an Ecto many_to_many relationship and generates (or uses the 
  provided) edge module as the intermediary schema. 

  Since the edge collection uses the full `_id` instead of the `_key` for the `_from` and `_to` 
  fields, we can't use the `:id` field. Schemas actually have an additional field which is 
  `:__id__` and stores the `_id` value. 

  ## Creating an edge

  Defining an edge is similar to how you would define a collection.

  When defining an edge schema you must define the `:from` and `:to` fields on the schema. You can
  use the `edge_fields/0` function as a shortcut to define these fields.

  A `changeset/2` function is automatically defined on the custom schema module but this must be 
  overridden this so that you can cast and validate the custom fields. The `edges_changeset/2` 
  method should be called to automatically implement the casting and validation of the `_from` and 
  `_to` fields. It does not have to be before any custom field operations but it good convention to 
  do so.

  ### Example

      defmodule MyProject.UserPosts do
        use ArangoXEcto.Edge,
            from: User,
            to: Post

        import Ecto.Changeset

        schema "user_posts" do
          edge_fields()

          field(:type, :string)
        end

        def changeset(edge, attrs) do
          edges_changeset(edge, attrs)
          |> cast(attrs, [:type])
          |> validate_required([:type])
        end
      end

  ## Multiple from and to schemas

  Unlike in a regular many-to-many relationship, edges in ArangoDB can have multiple schemas
  associated with it in the same from/to fields. In ArangoXEcto this is represented by using a list
  for the `from` and `to` options when defining an edge. For example, you could have an edge like
  the following.

      defmodule MyProject.MyContent do
        use ArangoXEcto.Edge,
            from: User,
            to: [Post, Comment]

        ...
      end
  """
  use ArangoXEcto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  defstruct [:_from, :to]

  @callback changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()

  defmacro __using__(opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)

    quote do
      use ArangoXEcto.Schema
      import unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @from unquote(from)
      @to unquote(to)

      @doc """
      Default Changeset for an Edge

      Should be overridden when using custom fields.
      """
      @spec changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
      def changeset(edge, attrs) do
        unquote(__MODULE__).edges_changeset(edge, attrs)
      end

      @doc """
      Defines that this schema is an edge
      """
      def __edge__, do: true

      defoverridable unquote(__MODULE__)
    end
  end

  @doc """
  Macro to define the required edge fields i.e. `_from` and `_to`.

  This is required when using a custom edge schema and can be used as below.

      schema "user_posts" do
        edge_fields()

        field(:type, :string)
      end

  The options passed are directly supplied to the 
  ArangoXEcto.Association.EdgeMany relation.
  """
  defmacro edge_fields(opts \\ []) do
    quote do
      opts = unquote(opts)

      edge_many(:from, @from, Keyword.put(opts, :key, :_from))
      edge_many(:to, @to, Keyword.put(opts, :key, :_to))
    end
  end

  @doc """
  Default changeset for an edge.

  Casts and requires the `_from` and `_to` fields. This will also verify the format of both fields to match that of
  an Arango id.

  Any custom changeset should first use this changeset.

  Direct use of the `edges_changeset/2` function is discouraged unless per the use case mentioned above.

  ### Example

  To add a required `type` field, you could do the following:

      def changeset(edge, attrs) do
        edges_changeset(edge, attrs)
        |> cast(attrs, [:type])
        |> validate_required([:type])
      end
  """
  @spec edges_changeset(%__MODULE__{}, %{}) :: %__MODULE__{}
  def edges_changeset(edge, attrs) do
    edge
    |> cast(attrs, [:_from, :_to])
    |> validate_required([:_from, :_to])
  end
end
