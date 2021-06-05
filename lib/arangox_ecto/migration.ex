defmodule ArangoXEcto.Migration do
  @moduledoc """
  Defines Ecto Migrations for ArangoDB

  **NOTE: ArangoXEcto dynamically creates collections for you and this method is discouraged unless
  you need to define indexes.**

  Migrations must use this module, otherwise migrations will not work. To do this, replace
  `use Ecto.Migration` with `use ArangoXEcto.Migration`.

  Since ArangoDB is schemaless, no fields need to be provided, only the collection name. First create
  a collection struct using the `collection/2` function. Then pass the collection struct to the
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

  @type index_option ::
          {:type, atom}
          | {:unique, boolean}
          | {:sparse, boolean}
          | {:deduplication, boolean}
          | {:minLength, integer}
          | {:geoJson, boolean}
          | {:expireAfter, integer}

  defmodule Collection do
    @moduledoc false
    defstruct [:name, :type]

    @type t :: %__MODULE__{}
  end

  defmodule Index do
    @moduledoc false

    defstruct [
      :collection_name,
      :fields,
      :sparse,
      :unique,
      :deduplication,
      :minLength,
      type: :hash
    ]

    @type t :: %__MODULE__{}
  end

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

  ## Examples

      iex> collection("users")
      %Collection{name: "users", 2)

      iex> collection("users", :edge)
      %Collection{name: "users", 3)
  """
  @spec collection(String.t(), atom()) :: Collection.t()
  def collection(collection_name, type \\ :document) do
    %Collection{name: collection_name, type: collection_type(type)}
  end

  @doc """
  Creates an edge collection struct

  Same as passing `:edge` as the second parameter to `collection/2`.
  """
  @spec edge(String.t()) :: Collection.t()
  def edge(edge_name), do: collection(edge_name, :edge)

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

  ## Examples

  Create index on email field

      iex> index("users", [:email])
      %Index{collection_name: "users", fields: [:email]}

  Create dual index on email and ph_number fields

      iex> index("users", [:email, :ph_number])
      %Index{collection_name: "users", fields: [:email, :ph_number]}

  Create unique email index

      iex> index("users", [:email], unique: true)
      %Index{collection_name: "users", fields: [:email], [unique: true]}
  """
  @spec index(String.t(), [String.t()], [index_option]) :: Index.t()
  def index(collection_name, fields, opts \\ []) do
    keys =
      [collection_name: collection_name, fields: fields]
      |> Keyword.merge(opts)

    struct(Index, keys)
  end

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
  @spec create(%Collection{} | %Index{}) :: :ok | {:error, binary()}
  def create(%Collection{} = collection) do
    {:ok, conn} = get_db_conn()

    case Arangox.post(conn, "/_api/collection", Map.from_struct(collection)) do
      {:ok, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  def create(%Index{collection_name: collection_name} = index) do
    {:ok, conn} = get_db_conn()

    case Arangox.post(
           conn,
           "/_api/index?collection=" <> get_collection_name(collection_name),
           Map.from_struct(index)
         ) do
      {:ok, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  @doc """
  Deletes an object

  Will delete an object passed, can only be a collection, indexes cannot be deleted here.

  ## Example

      iex> drop(collection("users"))
      :ok
  """
  @spec drop(%Collection{}) :: :ok | {:error, binary()}
  def drop(%Collection{name: collection_name}) do
    {:ok, conn} = get_db_conn()

    # TODO: Check type??
    case Arangox.delete(conn, "/_api/collection/" <> get_collection_name(collection_name)) do
      {:ok, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  defp get_db_conn do
    config(pool_size: 1)
    |> Arangox.start_link()
  end

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

  defp collection_type(:document), do: 2
  defp collection_type(:edge), do: 3

  defp get_collection_name(name) when is_atom(name), do: Atom.to_string(name)
  defp get_collection_name(name) when is_binary(name), do: name
end
