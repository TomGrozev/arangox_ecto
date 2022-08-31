defmodule ArangoXEcto.Migration do
  @moduledoc """
  Defines Ecto Migrations for ArangoDB

  **NOTE: ArangoXEcto dynamically creates collections for you by default. Depending on your project architecture you may decide to use static migrations instead in which case this module will be useful.**

  Migrations must use this module, otherwise migrations will not work. To do this, replace
  `use Ecto.Migration` with `use ArangoXEcto.Migration`.

  Since ArangoDB is schemaless, no fields need to be provided, only the collection name. First create
  a collection struct using the `collection/3` function. Then pass the collection struct to the
  `create/1` function. To create indexes it is a similar process using the `index/3` function.
  **Collections must be created BEFORE indexes.**

  To drop the collection on a migration down, do the same as creation except use the `drop/1` function
  instead of the `create/1` function. Indexes are automatically removed when the collection is removed
  and cannot be deleted using the `drop/1` function.

  ## Example

      defmodule MyProject.Repo.Migrations.CreateUsers do
        use ArangoXEcto.Migration

        def up do
          create(collection(:users))

          create(index("users", [:email]))
        end

        def down do
          drop(collection(:users))
        end
      end
  """

  require Logger

  alias ArangoXEcto.Migration.{Collection, Index}

  defmacro __using__(_) do
    # Init conn
    quote do
      import ArangoXEcto.Migration
    end
  end

  @doc """
  Creates a collection struct

  Used to in functions that perform actions on the database.

  Accepts a collection type parameter that can either be `:document` or `:edge`, otherwise it will
  raise an error. The default option is `:document`.


  ## Options

  Accepts an options parameter as the third argument. For available keys please refer to the [ArangoDB API doc](https://www.arangodb.com/docs/stable/http/collection-creating.html).

  ## Examples

      iex> collection("users")
      %ArangoXEcto.Migration.Collection{name: "users", type: 2)

      iex> collection("users", :edge)
      %ArangoXEcto.Migration.Collection{name: "users", type: 3)

      iex> collection("users", :document, keyOptions: %{type: :uuid})
      %ArangoXEcto.Migration.Collection{name: "users", type: 2, keyOptions: %{type: :uuid})
  """
  @spec collection(String.t(), atom(), [Collection.collection_option()]) :: Collection.t()
  def collection(collection_name, type \\ :document, opts \\ []),
    do: Collection.new(collection_name, type, opts)

  @doc """
  Creates an edge collection struct

  Same as passing `:edge` as the second parameter to `collection/3`.
  """
  @spec edge(String.t(), [Collection.collection_option()]) :: Collection.t()
  def edge(edge_name, opts \\ []), do: collection(edge_name, :edge, opts)

  @doc """
  Creates an index struct

  Default index type is a hash. To change this pass the `:type` option in options.

  ## Options

  Options only apply to the creation of indexes and has no effect when using the `drop/1` function.

  - `:type` - The type of index to create
    - Accepts: `:fulltext`, `:geo`, `:hash`, `:persistent`, `:skiplist` or `:ttl`
  - `:unique` - If the index should be unique, defaults to false (hash, persistent & skiplist only)
  - `:sparse` - If index should be spares, defaults to false (hash, persistent & skiplist only)
  - `:deduplication` - If duplication of array values should be turned off, defaults to true (hash & skiplist only)
  - `:minLength` - Minimum character length of words to index (fulltext only)
  - `:geoJson` -  If a geo-spatial index on a location is constructed and geoJson is true, then the order
  within the array is longitude followed by latitude (geo only)
  - `:expireAfter` - Time in seconds after a document's creation it should count as `expired` (ttl only)
  - `:name` - The name of the index (usefull for phoenix constraints)

  ## Examples

  Create index on email field

      iex> index("users", [:email])
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email]}

  Create dual index on email and ph_number fields

      iex> index("users", [:email, :ph_number])
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email, :ph_number]}

  Create unique email index

      iex> index("users", [:email], unique: true)
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email], unique: true}
  """
  @spec index(String.t(), [atom() | String.t()], [Index.index_option()]) :: Index.t()
  def index(collection_name, fields, opts \\ []), do: Index.new(collection_name, fields, opts)

  @doc """
  Creates an object

  Will create the passed object, either a collection or an index.

  ## Examples

  Create a collection

      iex> create(collection("users"))
      :ok

  Create an index

      iex> create(index("users", [:email])
      :ok
  """
  @spec create(Collection.t() | Index.t()) :: :ok | {:error, binary()}
  def create(collection_or_index, conn \\ nil)

  def create(%Collection{} = collection, conn) do
    {:ok, conn} = get_db_conn(conn)

    args =
      collection
      |> Map.from_struct()

    args = :maps.filter(fn _, v -> not is_nil(v) end, args)

    case Arangox.post(conn, "/_api/collection", args) do
      {:ok, _} ->
        :ok

      {:error, %{status: status, message: message}} ->
        msg = "#{status} - #{message}"

        Logger.debug("#{inspect(__MODULE__)}.create", %{
          "#{inspect(__MODULE__)}.create-collection" => %{collection: collection, message: msg}
        })

        {:error, msg}
    end
  end

  def create(%Index{collection_name: collection_name} = index, conn) do
    {:ok, conn} = get_db_conn(conn)

    case Arangox.post(
           conn,
           "/_api/index?collection=#{collection_name}",
           Map.from_struct(index)
         ) do
      {:ok, _} ->
        :ok

      {:error, %{status: status, message: message}} ->
        msg = "#{status} - #{message}"

        Logger.debug("#{inspect(__MODULE__)}.create", %{
          "#{inspect(__MODULE__)}.create-index" => %{index: index, message: msg}
        })

        {:error, msg}
    end
  end

  @doc """
  Deletes an object

  Will delete an object passed, can only be a collection, indexes cannot be deleted here. This is because indexes have a randomly generated id and this needs to be known to delete the index, for now this is outside the scope of this project.

  ## Example

      iex> drop(collection("users"))
      :ok
  """
  @spec drop(Collection.t()) :: :ok | {:error, binary()}
  def drop(%Collection{name: collection_name}, conn \\ nil) do
    {:ok, conn} = get_db_conn(conn)

    case Arangox.delete(conn, "/_api/collection/#{collection_name}") do
      {:ok, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  defp get_db_conn(nil) do
    config(pool_size: 1)
    |> Arangox.start_link()
  end

  defp get_db_conn(repo) when is_atom(repo), do: get_db_conn(nil)

  defp get_db_conn(conn), do: {:ok, conn}

  defp get_default_repo! do
    case Mix.Ecto.parse_repo([])
         |> List.first() do
      nil -> raise "No Default Repo Found"
      repo -> repo
    end
  end

  defp config(opts) do
    get_default_repo!().config()
    |> Keyword.merge(opts)
  end
end
