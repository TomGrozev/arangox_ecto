defmodule ArangoXEcto.View.Link do
  @moduledoc """
  Defines the structure of a link

  This follows the format of the link properties defined in ArangoDB. For more
  information [check out the ArangoDB docs](https://www.arangodb.com/docs/stable/arangosearch-views.html#link-properties).

  ## Example

    %ArangoXEcto.View.Link{
      includeAllFields: true,
      fields: %{
        name: %ArangoXEcto.View.Link{
          analyzers: [:text_en]
        }
      }
    }

  """
  @moduledoc since: "1.3.0"

  require Logger

  defstruct [
    :analyzers,
    :fields,
    :includeAllFields,
    :nested,
    :trackListPositions,
    :storeValues,
    :inBackground
  ]

  @type t :: %__MODULE__{
          analyzers: list(atom()),
          fields: %{atom() => t()},
          includeAllFields: boolean(),
          nested: %{atom() => t()},
          trackListPositions: boolean(),
          storeValues: String.t(),
          inBackground: boolean()
        }

  @doc """
  Validates a link

  This checks the types and strucute of a provided link struct.

  If a link is invalid for any reason this will return false. Using this allows for validation before
  sending to the DB.
  """
  @spec valid?(t()) :: :ok | {:error, String.t()}
  def valid?(%__MODULE__{} = link) do
    with :ok <- validate_analyzers(link.analyzers),
         :ok <- validate_fields(link.fields),
         :ok <- validate_nested(link.nested),
         :ok <- validate_options(link) do
      true
    else
      {:error, reason} ->
        Logger.debug("Invalid Link: #{reason}")

        false
    end
  end

  @doc """
  Converts to a map for api call

  This will convert any structs into maps in a deeply nested link definition.
  """
  @spec to_map(t()) :: map()
  def to_map(link) do
    %{
      analyzers: link.analyzers,
      fields: map_of_links(link.fields),
      includeAllFields: link.includeAllFields,
      nested: map_of_links(link.nested),
      trackListPositions: link.trackListPositions,
      storeValues: link.storeValues,
      inBackground: link.inBackground
    }
    |> remove_nil_values()
  end

  ###########
  # Helpers #
  ###########

  defp map_of_links(nil), do: nil

  defp map_of_links(links),
    do: Enum.reduce(links, %{}, fn {k, link}, acc -> Map.put(acc, k, to_map(link)) end)

  defp validate_analyzers(nil), do: :ok

  defp validate_analyzers(analyzers) do
    if is_list(analyzers) and Enum.all?(analyzers, &is_atom/1) do
      :ok
    else
      {:error, "Invalid analyzers"}
    end
  end

  defp validate_fields(nil), do: :ok

  defp validate_fields(fields) do
    if is_map(fields) and Enum.all?(fields, fn {_key, link} -> valid?(link) end) do
      :ok
    else
      {:error, "Invalid fields"}
    end
  end

  defp validate_nested(nil), do: :ok

  defp validate_nested(nested) do
    if is_map(nested) and Enum.all?(nested, fn {_key, link} -> valid?(link) end) do
      :ok
    else
      {:error, "Invalid nested fields"}
    end
  end

  defp validate_options(%__MODULE__{} = link) do
    if valid_option?(link.includeAllFields) and valid_option?(link.trackListPositions) and
         valid_option?(link.storeValues) and valid_option?(link.inBackground) do
      :ok
    else
      {:error, "Invalid link options"}
    end
  end

  defp valid_option?(option), do: is_boolean(option) or is_nil(option)

  defp remove_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_k, v}, acc when is_nil(v) ->
        acc

      {k, v}, acc ->
        Map.put(acc, k, v)
    end)
  end
end
