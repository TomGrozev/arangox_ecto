defmodule ArangoXEcto.Edge do
  @moduledoc """
  Edge schema required fields definition
  """
  use ArangoXEcto.Schema

  import Ecto.Changeset

  require ArangoXEcto.Schema.Fields

  alias ArangoXEcto.Schema.Fields

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

  defmacro edge_fields do
    quote do
      require unquote(Fields)

      unquote(Fields).define_fields(:edge)
    end
  end

  @after_compile
  schema "" do
    Fields.define_fields(:edge)
  end

  @doc """
  Validates the required fields for an edge
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
