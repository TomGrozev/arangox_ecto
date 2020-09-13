defmodule ArangoXEcto do
  @moduledoc """
  Methods for interacting with ArangoDB
  """
  alias ArangoXEcto.Edge

  @type query :: binary()
  @type vars :: keyword() | map()
  @type mod :: Ecto.Schema.t()

  @doc """
  Runs a raw AQL query on the database.
  """
  @spec aql_query(Ecto.Repo.t(), query(), vars(), [DBConnection.option()]) ::
          {:ok | :error, map()}
  def aql_query(repo, query, vars \\ [], opts \\ []) do
    conn = gen_conn_from_repo(repo)

    Arangox.transaction(
      conn,
      fn cursor ->
        stream = Arangox.cursor(cursor, query, vars)

        Enum.reduce(stream, [], fn resp, acc ->
          acc ++ resp.body["result"]
        end)
      end,
      opts
    )
  end

  @doc """
  Creates an edge between two modules

  This can create an edge collection dynamically if no additional fields are required,
  otherwise an edge schema needs to be specified.

  The collection name can be passed as an option or is obtained from the provided schema,
  otherwise it is generated dynamically.
  """
  @spec create_edge(Ecto.Repo.t(), mod(), mod(), keyword()) :: map()
  def create_edge(repo, mod1, mod2, opts \\ [])

  def create_edge(repo, mod1, mod2, [edge: edge_module, fields: _fields] = opts) do
    id1 = struct_id(mod1)
    id2 = struct_id(mod2)

    edge_module
    |> validate_ecto_schema()
    |> validate_edge_module()
    |> edge_module()
    |> do_create_edge(repo, id1, id2, opts)
  end

  def create_edge(repo, mod1, mod2, opts) do
    id1 = struct_id(mod1)
    id2 = struct_id(mod2)

    edge_module(opts, mod1, mod2)
    |> do_create_edge(repo, id1, id2, opts)
  end

  # TODO: Maybe remove
  @doc """
  Same as create_edge/4 but specific for custom edge and fields
  """
  @spec create_edge(Ecto.Repo.t(), mod(), mod(), mod(), map(), keyword()) :: map()
  def create_edge(repo, mod1, mod2, edge, %{} = fields, opts \\ []) do
    opts =
      opts
      |> Keyword.merge(edge: edge, fields: fields)

    create_edge(repo, mod1, mod2, opts)
  end

  ###############
  ##  Helpers  ##
  ###############

  defp gen_conn_from_repo(repo) do
    %{pid: conn} = Ecto.Adapter.lookup_meta(repo)

    conn
  end

  defp do_create_edge(module, repo, id1, id2, opts) do
    module
    |> maybe_create_edges_collection(repo)
    |> edge_changeset(id1, id2, opts)
    |> repo.insert!()
  end

  defp edge_module(module), do: struct(module)

  defp edge_module([collection_name: name], _, _), do: create_edge_struct(name)

  defp edge_module(_, mod1, mod2), do: create_edge_struct(gen_edge_collection_name(mod1, mod2))

  defp create_edge_struct(name) do
    %Edge{}
    |> Ecto.put_meta(source: name)
  end

  defp gen_edge_collection_name(mod1, mod2) do
    name1 = source_name(mod1)
    name2 = source_name(mod2)

    # TODO: Think of naming convention (make sure is unique)
    "#{name1}_#{name2}"
  end

  defp source_name(%schema{}) do
    schema.__schema__(:source)
  end

  defp struct_id(%{id: id} = struct) do
    source = source_name(struct)

    "#{source}/#{id}"
  end

  defp validate_ecto_schema(module) do
    case Keyword.has_key?(module.__info__(:functions), :__schema__) do
      true -> module
      false -> raise "#{module} is not an Ecto Schema"
    end
  end

  defp validate_edge_module(module) do
    fields = module.__schema__(:fields)

    [:_from, :_to]
    |> Enum.all?(&Enum.member?(fields, &1))
    |> case do
      true -> module
      false -> raise "#{module} is not an Edge"
    end
  end

  defp edge_changeset(%module{} = struct, id1, id2, opts) do
    attrs =
      Keyword.get(opts, :fields, %{})
      |> Map.merge(%{_from: id1, _to: id2})

    try do
      Kernel.apply(module, :changeset, [struct, attrs])
    rescue
      UndefinedFunctionError ->
        Edge.edges_changeset(struct, attrs)
    end
  end

  defp maybe_create_edges_collection(struct, repo) do
    conn = gen_conn_from_repo(repo)
    collection_name = Map.get(struct.__meta__, :source)

    Arangox.get(conn, "/_api/collection/#{collection_name}")
    |> case do
      {:ok, _request, %Arangox.Response{body: %{"type" => 3, "isSystem" => false}}} ->
        struct

      {_status, _any} ->
        create_edges_collection(conn, collection_name)

        struct
    end
  end

  defp create_edges_collection(conn, collection_name) do
    Arangox.post!(conn, "/_api/collection", %{name: collection_name, type: 3})
  end
end
