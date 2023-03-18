defmodule ArangoXEcto.Edge do
  @moduledoc """
  Defines an Arango Edge collection as an Ecto Schema Module.

  Edge modules are dynamically created in the environment if they don't already exist. For more on how edge modules
  are dynamically generated, please read `ArangoXEcto.edge_module/3`.
  This will define the required fields of an edge (`_from` and `_to`) and will define the default changeset.

  Edges utilise Ecto relationships so that the powerful Ecto features can be used. Each Node requires a relationship
  to be set, either a `outgoing/3` or `incoming/3`. Behind the scenes this creates an Ecto many_to_many relationship
  and generates (or uses the provided) edge module as the intermediary schema.
  Since the edge collection uses the full `_id` instead of the `_key` for the `_from` and `_to` fields, once
  using any of the previously specified relationships a `__id__` field will be added to structs that will store
  the value of the `_id` field so that relations can be loaded by Ecto.

  ## Extending Edge Schemas

  If you need to add additional fields to an edge, you can do so by creating your own edge module
  and defining the required fields as well as any additional fields. Luckily there are some helper macros
  so you don't have to do this manually again.

  When using a custom edge module, it must be passed to the relationship macros in the nodes using the `:edge`
  option, read more about these relationships at `ArangoXEcto.Schema`. Additionally, the `:edge` option must
  also be passed to the `ArangoXEcto.create_edge/4` function.

  A custom schema module must use this module by adding `use ArangoXEcto.Edge, from: FromSchema, to: ToSchema`.

  When defining the fields in your schema, make sure to call `edge_fields/1`. This will add the `_from`
  and `_to` foreign keys to the schema. It does not have to be before any custom fields but it good convention
  to do so.

  A `changeset/2` function is automatically defined on the custom schema module but this must be overridden
  this so that you can cast and validate the custom fields. The `edges_changeset/2` method should be called
  to automatically implement the casting and validation of the `_from` and `_to` fields. It does not have
  to be before any custom field operations but it good convention to do so.

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
  """
  defmacro edge_fields do
    quote do
      belongs_to(:from, @from, foreign_key: :_from, references: :__id__)
      belongs_to(:to, @to, foreign_key: :_to, references: :__id__)
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
