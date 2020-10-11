defmodule ArangoXEcto.Edge do
  @moduledoc """
  Defines an Arango Edge collection as an Ecto Schema Module.

  Edge modules are dynamically created in the environment if they don't already exist.
  This will define the required fields of an edge (`_from` and `_to`) and will define the default changeset.

  Collections in ArangoDB are automatically created if they don't exist already.

  ## Extending Edge Schemas

  If you need to add additional fields to an edge, you can do so by creating your own edge module
  and defining the required fields as well as any additional fields. Luckily there are some helper macros
  so you don't have to do this manually again.

  A custom schema module must use this module by adding `use ArangoXEcto.Edge`.

  When defining the fields in your schema, make sure to call `edge_fields/1`. This will add the `_from`
  and `_to` fields to the schema. It does not have to be before any custom fields but it good convention
  to do so.

  A `changeset/2` function is automatically defined on the custom schema module but this must be overridden
  this so that you can cast and validate the custom fields. The `edges_changeset/2` method should be called
  to automatically implement the casting and validation of the `_from` and `_to` fields. It does not have
  to be before any custom field operations but it good convention to do so.

  ### Example

      defmodule MyProject.UserPosts do
        use ArangoXEcto.Edge
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

  require ArangoXEcto.Schema.Fields

  alias ArangoXEcto.Schema.Fields

  @type t :: %__MODULE__{}

  @callback changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()

  defmacro __using__(_opts) do
    quote do
      use ArangoXEcto.Schema
      import unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @doc """
      Default Changeset for an Edge

      Should be overridden when using custom fields.
      """
      @spec changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
      def changeset(edge, attrs) do
        unquote(__MODULE__).edges_changeset(edge, attrs)
      end

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
      require unquote(Fields)

      unquote(Fields).define_fields(:edge)
    end
  end

  schema "" do
    Fields.define_fields(:edge)
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
  def edges_changeset(edge, attrs) do
    edge
    |> cast(attrs, [:_from, :_to])
    |> validate_required([:_from, :_to])
    |> validate_id([:_from, :_to])
  end

  defp validate_id(changeset, fields) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate_format(&2, &1, ~r/[a-zA-Z0-9]+\/[a-zA-Z0-9]+/))
  end
end
