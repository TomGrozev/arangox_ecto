defmodule ArangoXEcto do
  @moduledoc """
  Methods for interacting with ArangoDB that aren't through Ecto.

  This allows for easy interaction with graph functions of Arango. Using Ecto's relations for edge relations was tried
  but it was found to be too much of a 'hacky' solution. Using separate functions that still utilise Ecto document
  queries was found to be the optimal solution.
  """
  alias ArangoXEcto.Edge

  @type query :: binary()
  @type vars :: keyword() | map()
  @type mod :: Ecto.Schema.t()

  @doc """
  Runs a raw AQL query on the database.

  This will create a transaction and cursor on Arango and run the raw query.

  If there is an error in the query such as a syntax error, an `Arangox.Error` will be raised.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `query` - The AQL query string to execute
  - `vars` - A keyword list or a map with the values for variables in the query
  - `opts` - Options to be passed to `DBConnection.transaction/3`

  ## Examples

      iex> ArangoXEcto.aql_query(
            Repo,
            "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
            fname: "John",
            lname: "Smith"
          )
      {:ok,
      [
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
      ]}
  """
  @spec aql_query(Ecto.Repo.t(), query(), vars(), [DBConnection.option()]) ::
          {:ok, map()} | {:error, any()}
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

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `from` - The Ecto Schema struct to use for the from vertex
  - `to` - The Ecto Schema struct to use for the to vertex
  - `opts` - Options to use

  ## Options

  Accepts the following options:

  - `:edge` - A specific edge module to use for the edge. This is required for any additional fields on the edge. Overrides `collection_name`.
  - `:fields` - The values of the fields to set on the edge. Requires `edge` to be set otherwise it is ignored.
  - `:collection_name` - The name of the collection to use.

  ## Examples

      iex> ArangoXEcto.create_edge(Repo, user1, user2)
      %ArangoXEcto.Edge{_from: "users/12345", _to: "users/54321"}

  Create an edge with a specific edge collection name

      iex> ArangoXEcto.create_edge(Repo, user1, user2, collection_name: "friends")
      %ArangoXEcto.Edge{_from: "users/12345", _to: "users/54321"}

  Create a edge schema and use it to create an edge relation

      defmodule UserPosts do
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

      iex> ArangoXEcto.create_edge(Repo, user1, user2, edge: UserPosts, fields: %{type: "wrote"})
      %ArangoXEcto.Edge{_from: "users/12345", _to: "users/54321"}

  """
  @spec create_edge(Ecto.Repo.t(), mod(), mod(), keyword()) :: map()
  def create_edge(repo, from, to, opts \\ [])

  def create_edge(repo, from, to, [edge: edge_module, fields: _fields] = opts) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    edge_module
    |> validate_ecto_schema()
    |> validate_edge_module()
    |> edge_module()
    |> do_create_edge(repo, from_id, to_id, opts)
  end

  def create_edge(repo, from, to, opts) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    edge_module(opts, from, to)
    |> do_create_edge(repo, from_id, to_id, opts)
  end

  # TODO: Maybe remove
  @doc """
  Same as create_edge/4 but specific for custom edge and fields.
  """
  @spec create_edge(Ecto.Repo.t(), mod(), mod(), mod(), map(), keyword()) :: map()
  def create_edge(repo, from, to, edge, %{} = fields, opts \\ []) do
    opts =
      opts
      |> Keyword.merge(edge: edge, fields: fields)

    create_edge(repo, from, to, opts)
  end

  @doc """
  Deletes an edge that matches the query

  If field conditions are set then those conditions must be true to delete.
  """
  @spec delete_edge(Ecto.Repo.t(), mod(), mod(), keyword()) :: map()
  def delete_edge(repo, from, to, opts) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    edge_module(opts, from, to)
    |> do_delete_edge(repo, from_id, to_id, opts)
  end

  @doc """
  Gets an ID from a schema struct
  """
  @spec get_id_from_struct(mod()) :: binary()
  def get_id_from_struct(struct), do: struct_id(struct)

  @doc """
  Converts raw output of a query into a struct
  """
  @spec raw_to_struct(map() | [map()], Ecto.Schema.t()) :: struct()
  def raw_to_struct(maps, module) when is_list(maps) do
    Enum.map(maps, & raw_to_struct(&1, module))
  end

  def raw_to_struct(map, module) when is_map(map) do
    args = patch_map(map)
    |> filter_keys_for_struct()

    struct(module, args)
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
    |> ensure_collections_exists(repo, id1, id2)
    |> edge_changeset(id1, id2, opts)
    |> repo.insert!()
  end

  defp do_delete_edge(module, repo, id1, id2, opts) do
    module
    |> collection_name_from_struct()
    |> collection_exists!(repo)

  end

  defp ensure_collections_exists(module, repo, id1, id2) do
    collection_from_id(id1)
    |> collection_exists!(repo)

    collection_from_id(id2)
    |> collection_exists!(repo)

    module
  end

  defp collection_exists!(collection_name, repo) do
    case collection_exists?(repo, collection_name) do
      true ->
        true

      false ->
        raise "Collection #{collection_name} does not exist"
    end
  end

  defp collection_from_id(id), do: source_name(id)

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

  defp source_name(id) when is_binary(id) do
    String.split(id, "/", trim: true)
    |> List.first()
  end

  defp struct_id(%{id: id} = struct) do
    source = source_name(struct)

    "#{source}/#{id}"
  end

  defp struct_id(id) when is_binary(id) do
    case String.match?(id, ~r/[a-zA-Z0-9]+\/[a-zA-Z0-9]+/) do
      true -> id
      false -> raise "Invalid format for ArangoDB document ID"
    end
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

  defp collection_name_from_struct(struct) do
    Map.get(struct.__meta__, :source)
  end

  defp maybe_create_edges_collection(struct, repo) do
    collection_name = collection_name_from_struct(struct)

    collection_exists?(repo, collection_name, 3)
    |> case do
      true ->
        struct

      false ->
        create_edges_collection(repo, collection_name)

        struct
    end
  end

  defp collection_exists?(repo, collection_name, type \\ 2) when is_binary(collection_name) do
    conn = gen_conn_from_repo(repo)

    Arangox.get(conn, "/_api/collection/#{collection_name}")
    |> case do
      {:ok, _request, %Arangox.Response{body: %{"type" => ^type, "isSystem" => false}}} ->
        true

      _any ->
        false
    end
  end

  defp create_edges_collection(repo, collection_name) do
    conn = gen_conn_from_repo(repo)

    Arangox.post!(conn, "/_api/collection", %{name: collection_name, type: 3})
  end

  defp patch_map(map) do
    for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
  end

  defp filter_keys_for_struct(map) do
    key = Map.get(map, :_key)

    with map = Map.put(map, :id, key),
         {_, map} = Map.pop(map, :_id),
         {_, map} = Map.pop(map, :_rev),
         {_, map} = Map.pop(map, :_key),
         do: map
  end
end
