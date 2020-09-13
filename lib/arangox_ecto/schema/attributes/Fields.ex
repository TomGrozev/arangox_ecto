defmodule ArangoXEcto.Schema.Attributes.Fields do
  @moduledoc """
  Defines required fields for schemas
  """

  @doc """
  Returns the required fields for a specific type of object
  """
  @spec required_fields(binary()) :: [tuple()]
  def required_fields(type \\ :doc)

  def required_fields(:doc), do: []

  def required_fields(:edge) do
    [
      {:_from, :string},
      {:_to, :string}
    ]
  end

  @doc """
  Defines the required fields for type
  """
  @spec define_fields(atom()) :: Macro.t()
  defmacro define_fields(type) do
    fields = required_fields(type)

    quote do
      unquote(fields)
      |> Enum.each(fn
        {name, type} ->
          field(name, type)

        {name, type, opts} ->
          field(name, type, opts)
      end)
    end
  end
end
