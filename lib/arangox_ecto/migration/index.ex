defmodule ArangoXEcto.Migration.Index do
  @moduledoc """
  Represents a collection index in ArangoDB

  The attributes in this struct are directly passed to the
  ArangoDB API for creation. No validation is done on the
  attributes and is left to the database to manage.
  """

  @enforce_keys [:collection_name]
  defstruct [
    :collection_name,
    :fields,
    :sparse,
    :unique,
    :deduplication,
    :minLength,
    :geoJson,
    :expireAfter,
    :name,
    type: :hash
  ]

  @type t :: %__MODULE__{}

  @type index_option ::
          {:type, atom}
          | {:unique, boolean}
          | {:sparse, boolean}
          | {:deduplication, boolean}
          | {:minLength, integer}
          | {:geoJson, boolean}
          | {:expireAfter, integer}
          | {:name, atom}

  @doc """
  Creates a new Index struct
  """
  @spec new(String.t(), [atom() | String.t()], [index_option()]) :: t()
  def new(name, fields, opts \\ []) do
    keys =
      [collection_name: name, fields: fields]
      |> Keyword.merge(opts)

    struct(__MODULE__, keys)
  end
end
