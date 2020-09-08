defmodule ArangoXEcto.Migration do
  @type index_option ::
          {:type, atom}
          | {:unique, boolean}
          | {:sparse, boolean}
          | {:deduplication, boolean}
          | {:minLength, integer}

  defmodule Collection do
    defstruct [:name, :type]

    @type t :: %__MODULE__{}
  end

  defmodule Index do
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

  @spec collection(String.t(), atom()) :: Collection.t()
  def collection(collection_name, type \\ :document) do
    %Collection{name: collection_name, type: collection_type(type)}
  end

  @spec edge(String.t()) :: Collection.t()
  def edge(edge_name), do: collection(edge_name, :edge)

  @spec index(String.t(), [String.t()], [index_option]) :: Index.t()
  def index(collection_name, fields, opts \\ []) do
    keys =
      [collection_name: collection_name, fields: fields]
      |> Keyword.merge(opts)

    struct(Index, keys)
  end

  def create(%Collection{} = collection) do
    {:ok, conn} = get_db_conn()

    case Arangox.post(conn, "/_api/collection", Map.from_struct(collection)) do
      {:ok, _, _} -> :ok
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
      {:ok, _, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  def drop(%Collection{name: collection_name}) do
    {:ok, conn} = get_db_conn()

    case Arangox.delete(conn, "/_api/collection/" <> get_collection_name(collection_name)) do
      {:ok, _, _} -> :ok
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
