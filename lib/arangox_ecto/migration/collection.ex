defmodule ArangoXEcto.Migration.Collection do
  @moduledoc """
  Represent a collection in ArangoDB

  The attributes in this struct are directly passed to the
  ArangoDB API for creation. No validation is done on the
  attributes and is left to the database to manage.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :waitForSync,
    :schema,
    :keyOptions,
    :type,
    :cacheEnabled,
    :numberOfShards,
    :shardKeys,
    :replicationFactor,
    :writeConcern,
    :distributeShardsLike,
    :shardingStrategy,
    :smartJoinAttribute
  ]

  @type t :: %__MODULE__{}

  @type collection_option ::
          {:waitForSync, boolean}
          | {:schema, map}
          | {:keyOptions, map}
          | {:cacheEnabled, boolean}
          | {:numberOfShards, integer}
          | {:shardKeys, String.t()}
          | {:replicationFactor, integer}
          | {:writeConcern, integer}
          | {:distributeShardsLike, String.t()}
          | {:shardingStrategy, String.t()}
          | {:smartJoinAttribute, String.t()}

  @doc """
  Creates a new Collection struct
  """
  @spec new(String.t(), atom(), [collection_option()]) :: t()
  def new(name, type \\ :document, opts \\ []) do
    keys =
      [name: name, type: collection_type(type)]
      |> Keyword.merge(opts)

    struct(__MODULE__, keys)
  end

  defp collection_type(:document), do: 2
  defp collection_type(:edge), do: 3
end
