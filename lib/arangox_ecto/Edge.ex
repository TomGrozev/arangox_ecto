defmodule ArangoXEcto.Edge do
  @moduledoc """
  Base Edge Schema.

  This module should be used such as `use ArangoXEcto.Edge` to create a custom edge schema.

  ## Example

      defmodule ArangoXEctoTest.Integration.UserPosts do
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

  Any custom changeset should first use this changeset. For example to add a required `type` field, you could do the
  following:

      def changeset(edge, attrs) do
        edges_changeset(edge, attrs)
        |> cast(attrs, [:type])
        |> validate_required([:type])
      end

  Direct use of the `edges_changeset/2` function is discouraged unless per the use case mentioned above.
  """
  def edges_changeset(edge, attrs) do
    edge
    |> cast(attrs, [:_from, :_to])
    |> validate_required([:_from, :_to])
    |> validate_id([:_from, :_to])
  end

  defp validate_id(changeset, fields) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate_format(&2, &1, ~r/[a-zA-Z0-9]+\/[a-zA-Z0-9]+/))

    changeset
  end
end
