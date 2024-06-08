defmodule ArangoXEcto do
  @moduledoc """
  Methods for interacting with ArangoDB that aren't through Ecto.

  This allows for easy interaction with graph functions of Arango. Using Ecto's relations for edge relations was tried
  but it was found to be too much of a 'hacky' solution. Using separate functions that still utilise Ecto document
  queries was found to be the optimal solution.
  """

  import Ecto.Query, only: [from: 2]

  alias ArangoXEcto.Adapter
  alias ArangoXEcto.Behaviour.Transaction
  alias ArangoXEcto.Edge
  alias ArangoXEcto.Migration

  @type query :: binary()
  @type vars :: keyword() | map()

  @doc """
  Runs a raw AQL query on the database.

  This will create a transaction and cursor on Arango and run the raw query.

  If there is an error in the query such as a syntax error, an `Arangox.Error` will be raised.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `query` - The AQL query string to execute
  - `vars` - A keyword list or a map with the values for variables in the query
  - `opts` - Options to be passed for the transaction

  Accepts any of the options accepted by DBConnection.transaction/3, as well as any of the following:

    :prefix - The prefix to use for the database. Defaults to the repo database.
    :read - An array of collection names or a single collection name as a binary to mark as read-only.
    :write - An array of collection names or a single collection name as a binary to mark as writable. If not set then no writes will be stored.
    :exclusive - An array of collection names or a single collection name as a binary.
    :properties - A list or map of additional body attributes to append to the request body when beginning a transaction.

  If doing a write operation, the `:write` operation must be passed. This is not explicitly required for read operations.

  ## Examples

      iex> ArangoXEcto.aql_query(
            Repo,
            "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
            fname: "John",
            lname: "Smith"
          )
      {:ok, {1, 
        [
          %{
            "_id" => "users/12345",
            "_key" => "12345",
            "_rev" => "_bHZ8PAK---",
            "first_name" => "John",
            "last_name" => "Smith"
          }
        ]}}
  """
  @spec aql_query(Ecto.Repo.t() | Ecto.Adapter.adapter_meta(), query(), vars(), [
          DBConnection.option()
        ]) ::
          {:ok, {non_neg_integer(), list(map)}} | {:error, any()}
  def aql_query(
        repo_or_meta,
        query,
        vars \\ [],
        opts \\ []
      )

  def aql_query(
        %{repo: repo, telemetry: telemetry, opts: default_opts} = adapter_meta,
        query,
        vars,
        opts
      ) do
    is_write_operation = String.match?(query, ~r/(update|remove) .+/i)

    {query, vars} = process_vars(query, vars)

    database = Adapter.get_database(repo, opts)

    opts = Adapter.with_log(telemetry, vars, [database: database] ++ opts ++ default_opts)

    try do
      Transaction.transaction(
        adapter_meta,
        opts,
        fn cursor ->
          default_properties = [options: %{fullCount: true}]

          opts =
            Keyword.update(
              opts,
              :properties,
              default_properties,
              &Keyword.merge(&1, default_properties)
            )

          stream = Arangox.cursor(cursor, query, vars, opts)

          Enum.reduce(
            stream,
            {0, []},
            fn resp, {_len, acc} ->
              len =
                if is_write_operation do
                  resp.body["extra"]["stats"]["writesExecuted"]
                else
                  resp.body["extra"]["stats"]["fullCount"]
                end

              {len, acc ++ resp.body["result"]}
            end
          )
        end
      )
    rescue
      e -> {:error, e}
    end
  end

  def aql_query(repo, query, vars, opts) when is_atom(repo) do
    adapter_meta = Ecto.Adapter.lookup_meta(repo)

    aql_query(adapter_meta, query, vars, opts)
  end

  @doc """
  Same as `ArangoXEcto.aql_query/4 but will raise an error.`

  If there is an error in the query such as a syntax error, an `Arangox.Error` will be raised.

  ## Examples

      iex> ArangoXEcto.aql_query!(
            Repo,
            "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
            fname: "John",
            lname: "Smith"
          )
       {1, [
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
      ]}
  """
  @spec aql_query!(Ecto.Repo.t() | Ecto.Adapter.adapter_meta(), query(), vars(), [
          DBConnection.option()
        ]) ::
          {non_neg_integer(), list(map)}
  def aql_query!(repo_or_meta, query, vars \\ [], opts \\ []) do
    case aql_query(repo_or_meta, query, vars, opts) do
      {:ok, res} -> res
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs an Arangox function using a repo

  This is simply a helper function that extracts the connection from the repo and runs a regular query.

  ## Parameters

  - `repo` - The Ecto repo module used for connection
  - `function` - An atom of the Arangox function to run
  - `path` - The path of the query
  - `body` - The body of the request
  - `headers` - The headers of the request
  - `opts` - The last opts arg passed to the function

  ## Supported Functions

  - `:abort`
  - `:cursor`
  - `:delete`
  - `:delete!`
  - `:get`
  - `:get!`
  - `:head`
  - `:head!`
  - `:options`
  - `:options!`
  - `:patch`
  - `:patch!`
  - `:post`
  - `:post!`
  - `:put`
  - `:put!`
  - `:request`
  - `:request!`
  - `:run`
  - `:status`
  - `:transaction` (use built in `Ecto.Repo.transaction/2` instead)

  ## Examples

      iex> ArangoXEcto.api_query(Repo, :get, "/_api/collection")
      {:ok, %Arangox.Response{body: ...}}

      iex> ArangoXEcto.api_query(Repo, :non_existent, "/_api/collection")
      ** (ArgumentError) Invalid function passed to `Arangox` module

  """
  @allowed_arangox_funcs [
    :abort,
    :cursor,
    :delete,
    :delete!,
    :get,
    :get!,
    :head,
    :head!,
    :options,
    :options!,
    :patch,
    :patch!,
    :post,
    :post!,
    :put,
    :put!,
    :request,
    :request!,
    :run,
    :status,
    :transaction
  ]
  @spec api_query(
          Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          atom(),
          Arangox.path(),
          Arangox.body(),
          Arangox.headers(),
          [
            DBConnection.option()
          ]
        ) :: {:ok, Arangox.Response.t()} | {:error, any()}
  def api_query(
        repo_or_meta,
        function,
        path,
        body \\ "",
        headers \\ %{},
        opts \\ []
      )

  def api_query(
        %{pid: pool, telemetry: telemetry, opts: default_opts},
        function,
        path,
        body,
        headers,
        opts
      ) do
    conn = Adapter.get_conn_or_pool(pool)

    opts = Adapter.with_log(telemetry, body, opts ++ default_opts)

    if function in @allowed_arangox_funcs and
         function in Keyword.keys(Arangox.__info__(:functions)) do
      Arangox.request(conn, function, path, body, headers, opts)
      |> do_result()
    else
      raise ArgumentError, "Invalid function [#{function}] passed to `Arangox` module"
    end
  end

  def api_query(repo, function, path, body, headers, opts) when is_atom(repo) do
    adapter_meta = Ecto.Adapter.lookup_meta(repo)

    api_query(adapter_meta, function, path, body, headers, opts)
  end

  @doc """
  Creates an edge between two modules

  This can create an edge collection dynamically if no additional fields are required,
  otherwise an edge schema needs to be specified.

  The collection name can be passed as an option or is obtained from the provided schema,
  otherwise it is generated dynamically.

  Since ArangoDB does not care about the order of the from and two options in anonymous graphs, the order of the
  from and to attributes used in this function will work either way.

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
      %UserUser{_from: "users/12345", _to: "users/54321"}

  Create an edge with a specific edge collection name

      iex> ArangoXEcto.create_edge(Repo, user1, user2, collection_name: "friends")
      %Friends{_from: "users/12345", _to: "users/54321"}

  Create a edge schema and use it to create an edge relation

      defmodule UserPosts do
        use ArangoXEcto.Edge,
            from: User,
            to: Post

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
      %UserPosts{_from: "users/12345", _to: "users/54321", from: #Ecto.Association.NotLoaded<association :from is not loaded>, to: #Ecto.Association.NotLoaded<association :to is not loaded>, type: "wrote"}

  """
  @spec create_edge(Ecto.Repo.t(), module(), module(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def create_edge(repo, from, to, opts \\ []) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    Keyword.get_lazy(opts, :edge, fn -> edge_module(from, to, opts) end)
    |> do_create_edge(repo, from_id, to_id, opts)
  end

  @doc """
  Creates a view defined by some view schema

  When in dynamic mode this will automatically create analyzers 
  and linked collections. If in static mode these need to be done 
  seperately in the migrations.

  For the analyzers to be automatically created in dynamic mode 
  the analyzers module needs to be passed as an option into the view
  module definition. See `ArangoXEcto.View` for more info.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `view` - The View Schema to be created
  - `opts` - Additional options to use for analyzer creation

  ## Options

  - `:prefix` - The prefix for the tenant to create analyzers for

  ## Examples

      iex> ArangoXEcto.create_view(Repo, MyApp.Views.UserSearch)
      {:ok, %Arangox.Response{}}

  If there is an error in the schema

      iex> ArangoXEcto.create_view(Repo, MyApp.Views.UserSearch)
      {:error, %Arangox.Error{}}

  """
  @doc since: "1.3.0"
  @spec create_view(Ecto.Repo.t(), ArangoXEcto.View.t(), Keyword.t()) ::
          :ok | {:error, Arangox.Error.t()}
  def create_view(repo, view, opts \\ []) do
    unless view?(view) do
      raise ArgumentError, "not a valid view schema"
    end

    # check if is dynamic mode
    if not Keyword.get(repo.config(), :static, true) do
      analyzer_module = view.__analyzer_module__()

      # create the analyzers if in dynamic mode
      if not is_nil(analyzer_module) do
        create_analyzers(repo, analyzer_module, opts)
      end

      # Create link collections if they don't exist in dynamic mode
      view.__view__(:links)
      |> Enum.each(fn {collection, _} ->
        maybe_create_collection(repo, collection)
      end)
    end

    name = view.__view__(:name)
    options = view.__view__(:options)
    links = view.__view__(:links)
    primary_sort = view.__view__(:primary_sort)
    stored_values = view.__view__(:stored_values)

    view_def = Migration.view(name, Keyword.merge(options, opts))

    subcommands =
      [add_link: links, add_sort: primary_sort, add_store: stored_values]
      |> Enum.reduce([], fn {type, list}, acc ->
        Enum.reduce(list, acc, fn {arg1, arg2}, acc2 ->
          [{type, arg1, arg2} | acc2]
        end)
      end)

    case repo.__adapter__().execute_ddl(repo, {:create, view_def, subcommands}, opts) do
      {:ok, [{:info, _, _}]} -> :ok
      {:ok, [{:error, reason, _}]} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates analyzers in a module

  This will first force delete any analyzers with the same name before creating
  the ones defined.

  In production you should be using migrations in static mode. This function 
  will be called when an analyzer module is passed to the `ArangoXEcto.Migration.create/2`
  function.

  When operating in dynamic mode the analyzers ae automatically created on view create,
  see `ArangoXEcto.create_view/2` for more info.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `analyzer_module` - The Analyzer module
  - `opts` - Additional options to use for analyzer creation

  ## Options

  - `:prefix` - The prefix for the tenant to create analyzers for

  ## Examples

      iex> ArangoXEcto.create_analyzers(Repo, MyApp.Analyzers)
      {:ok, [%Arangox.Response{}, ...]}

  If there is an error in and of the schemas

      iex> ArangoXEcto.create_analyzers(Repo, MyApp.Analyzers)
      {:error, [%Arangox.Response{}, ...], [%Arangox.Error{}, ...]}

  """
  @doc since: "1.3.0"
  @spec create_analyzers(Ecto.Repo.t(), ArangoXEcto.Analyzer.t(), Keyword.t()) ::
          :ok | {:error, [atom()], [{atom(), Arangox.Error.t()}]}
  def create_analyzers(repo, analyzer_module, opts \\ []) do
    analyzers = analyzer_module.__analyzers__()

    remove_existing_analyzers(repo, analyzers, opts)

    Enum.reduce(analyzers, {[], []}, fn analyzer, {success, fail} ->
      case repo.__adapter__().execute_ddl(repo, {:create, analyzer}, opts) do
        {:ok, [{:info, _, _}]} -> {[analyzer.name | success], fail}
        {:ok, [{:error, reason, _}]} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> case do
      {_, []} -> :ok
      {success, fail} -> {:error, success, fail}
    end
  end

  @doc """
  Creates a collection defined by some schema

  This function is only to be used in dynamic mode and will raise
  an error if called in static mode. Instead use migrations if
  in static mode.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `schema` - The Collection Schema to be created
  - `opts` - Additional options to pass

  ## Options 

  - `:prefix` - The prefix to use for database tenant collection creation

  ## Examples

      iex> ArangoXEcto.create_collection(Repo, MyApp.Users)
      :ok

  If there is an error in the schema

      iex> ArangoXEcto.create_collection(Repo, MyApp.Users)
      {:error, %Arangox.Error{}}

  """
  @spec create_collection(Ecto.Repo.t(), ArangoXEcto.Schema.t(), Keyword.t()) ::
          :ok | {:error, any()}
  def create_collection(repo, schema, opts \\ []) do
    if Keyword.get(repo.config(), :static, true) do
      raise("This function cannot be called in static mode. Please use migrations instead.")
    else
      # will throw if not a schema
      type = ArangoXEcto.schema_type!(schema)
      collection_name = source_name(schema)
      collection_opts = schema.__collection_options__() |> Keyword.put(:type, type)
      indexes = schema.__collection_indexes__()

      collection = Migration.collection(collection_name, collection_opts)

      meta = Ecto.Adapter.lookup_meta(repo)

      case repo.__adapter__().execute_ddl(meta, {:create, collection, []}, opts) do
        :ok ->
          maybe_create_indexes(meta, collection_name, indexes, opts)

        error ->
          error
      end
    end
  end

  @doc """
  Deletes all edges matching matching the query

  If the `:conditions` option is set then those conditions must be true to delete.

  To just delete one edge do so like any other Ecto Schema struct, i.e. using `Ecto.Repo` methods.

  ## Parameters

  - `repo` - The Ecto repo module to use for queries
  - `from` - The Ecto Schema struct to use for the from vertex
  - `to` - The Ecto Schema struct to use for the to vertex
  - `opts` - Options to use

  ## Options

  Accepts the following options:

  - `:edge` - A specific edge module to use for the edge. This is required for any additional fields on the edge. Overrides `:collection_name`.
  - `:collection_name` - The name of the collection to use.
  - `:conditions` - A keyword list of conditions to filter for edge deletion

  ## Examples

  Deletes all edges from user1 to user2

      iex> ArangoXEcto.delete_all_edges(Repo, user1, user2)
      :ok

  Deletes all edges from user1 to user2 in specific collection

      iex> ArangoXEcto.delete_all_edges(Repo, user1, user2, collection_name: "friends")
      :ok

  Deletes all edges from user1 to user2 that have matching conditions

      iex> ArangoXEcto.delete_all_edges(Repo, user1, user2, conditions: [type: "best_friend"])
      :ok
  """
  @spec delete_all_edges(Ecto.Repo.t(), module(), module(), Keyword.t()) :: :ok
  def delete_all_edges(repo, from, to, opts \\ []) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    Keyword.get_lazy(opts, :edge, fn ->
      edge_module(from, to, Keyword.put(opts, :create, false))
    end)
    |> do_delete_all_edges(repo, from_id, to_id, opts)
  end

  @doc """
  Gets an ID from a schema struct

  ## Parameters

  - `struct` - The Ecto struct

  ## Example

  If the User schema's collection name is `users` the following would be:

      iex> user = %User{id: "123456"}
      %User{id: "123456"}

      iex> ArangoXEcto.get_id_from_struct(user)
      "users/123456"
  """
  @spec get_id_from_struct(module()) :: binary()
  def get_id_from_struct(struct) when is_map(struct) or is_binary(struct), do: struct_id(struct)

  @doc """
  Gets an ID from a module and a key

  ## Parameters

  - `module` - Module to get the collection name from
  - `key` - The `_key` to use in the id

  ## Example

      iex> ArangoXEcto.get_id_from_module(User, "123456")
      "users/123456"
  """
  @spec get_id_from_module(Ecto.Schema.t(), binary()) :: binary()
  def get_id_from_module(module, key) when is_atom(module) and (is_atom(key) or is_binary(key)) do
    schema_type!(module)

    to_string(module.__schema__(:source)) <> "/" <> to_string(key)
  end

  def get_id_from_module(_, _), do: raise(ArgumentError, "Invalid module or key")

  @doc """
  Converts raw output of a query into a struct

  Transforms string map arguments into atom key map, adds id key and drops `_id`, `_key` and `_rev` keys.
  Then it creates a struct from filtered arguments using module.

  If a list of maps are passed then the maps are enumerated over.

  ## Parameters

  - `maps` - List of maps or singular map to convert to a struct
  - `module` - Module to use for the struct

  ## Example

      iex> {:ok, users} = ArangoXEcto.aql_query(
            Repo,
            "FOR user IN users RETURN user"
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

      iex> ArangoXEcto.raw_to_struct(users, User)
      [
        %User{
          id: "12345",
          first_name: "John",
          last_name: "Smith"
        }
      ]
  """
  @deprecated "Use load/2 instead"
  @spec raw_to_struct(map() | [map()], Ecto.Schema.t()) :: struct()
  def raw_to_struct(map, module) when is_list(map) and is_atom(module) do
    Enum.map(map, &raw_to_struct(&1, module))
  end

  def raw_to_struct(%{"_id" => _id, "_key" => _key} = map, module)
      when is_map(map) and is_atom(module) do
    schema_type!(module)

    args =
      patch_map(map)
      |> filter_keys_for_struct()

    struct(module, args)
  end

  def raw_to_struct(_, _), do: raise(ArgumentError, "Invalid input map or module")

  @doc """
  Loads raw map into ecto structs

  Uses `Ecto.Repo.load/2` to load a deep map result into ecto structs

  If a list of maps are passed then the maps are enumerated over.

  A list of modules can also be passes for possible types. The `_id`
  field is used to check against the module schemas. This is especially
  useful for querying against arango views where there may be multiple
  schema results returned.

  If a module is passed that isn't a Ecto Schema then an error will be
  raised.

  ## Parameters

  - `maps` - List of maps or singular map to convert to a struct
  - `module` - Module(s) to use for the struct

  ## Example

      iex> {:ok, users} = ArangoXEcto.aql_query(
            Repo,
            "FOR user IN users RETURN user"
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

      iex> ArangoXEcto.load(users, User)
      [
        %User{
          id: "12345",
          first_name: "John",
          last_name: "Smith"
        }
      ]
  """
  @spec load(map() | [map()], Ecto.Schema.t() | [Ecto.Schema.t()]) :: struct()
  def load(map, module) when is_atom(module),
    do: load(map, [module])

  def load(map, module) when is_list(map),
    do: Enum.map(map, &load(&1, module))

  def load(%{"_id" => id} = map, modules) do
    [source, _key] = String.split(id, "/")

    module =
      Enum.find(modules, fn mod ->
        schema_type!(mod)

        mod.__schema__(:source) == source
      end)

    Ecto.Repo.Schema.load(ArangoXEcto.Adapter, module, map)
    |> add_associations(module, map)
  end

  def load(%{__id__: id} = map, modules) do
    [source, _key] = String.split(id, "/")

    module =
      Enum.find(modules, fn mod ->
        schema_type!(mod)

        mod.__schema__(:source) == source
      end)

    struct(module, map)
    |> add_associations(module, map)
  end

  def load(_, _), do: raise(ArgumentError, "Invalid input map or module")

  @doc """
  Generates an edge schema dynamically

  If a collection name is not provided one will be dynamically generated. The naming convention
  is the names of the two modules is alphabetical order. E.g. `User` and `Post` will combine for a collection
  name of `post_user` and an edge module name of `PostUser`. This order is used to prevent duplicates if the
  from and to orders are switched.

  This will create the Ecto Module in the environment dynamically. It will create it under the closest
  common parent module of the passed modules plus the `Edges` alias. For example, if the modules were
  `MyApp.Apple.User` and `MyApp.Apple.Banana.Post` then the edge would be created at `MyApp.Apple.Edges.PostUser`.

  Returns the Edge Module name as an atom.

  ## Parameters

  - `from_module` - Ecto Schema Module for the from part of the edge
  - `to_module` - Ecto Schema Module for the to part of the edge
  - `opts` - Options passed for module generation

  ## Options

  - `:collection_name` - The name of collection to use instead of generating it

  ## Examples

      iex> ArangoXEcto.edge_module(MyProject.User, MyProject.Company, [collection_name: "works_for"])
      MyProject.Edges.WorksFor

      iex> ArangoXEcto.edge_module(MyProject.User, MyProject.Company)
      MyProject.Edges.CompanyUser
  """
  @spec edge_module(module(), module(), Keyword.t()) :: atom()
  def edge_module(from_module, to_module, opts \\ [])

  def edge_module(%from_module{}, %to_module{}, opts),
    do: edge_module(from_module, to_module, opts)

  def edge_module(from_module, to_module, opts) do
    case Keyword.fetch(opts, :collection_name) do
      {:ok, name} -> name
      :error -> gen_edge_collection_name(from_module, to_module)
    end
    |> create_edge_module(from_module, to_module, opts)
  end

  @doc """
  Returns the name of a database for prefix

  This simply prepends the tenant name to the database supplied in the repo config.

  ## Parameters

  - `repo` - The Ecto repo module to use for the query
  - `prefix` - The prefix to get the database name for
  """
  @spec get_prefix_database(Ecto.Repo.t(), String.t() | atom()) :: String.t()
  def get_prefix_database(repo, nil), do: get_repo_db(repo)
  def get_prefix_database(repo, prefix), do: "#{prefix}_" <> get_repo_db(repo)

  @doc """
  Checks if a collection exists

  This will return true if the collection exists in the database, matches the specified type and is not a system
  database, otherwise it will be false.

  ## Parameters

  - `repo` - The Ecto repo module to use for the query
  - `collection_name` - Name of the collection to check
  - `type` - The type of collection to check against, defaults to a regular document
  - `opts` - Options to be used, available options shown below, defaults to none

  ## Options

  - `:prefix` - The prefix to use for database collection checking

  ## Examples

  Checking a document collection exists

      iex> ArangoXEcto.collection_exists?(Repo, :users)
      true

  Checking an edge collection exists

      iex> ArangoXEcto.collection_exists?(Repo, "my_edge", :edge)
      true

  Checking a system document collection exists does not work

      iex> ArangoXEcto.collection_exists?(Repo, "_system_test")
      false

  Checking a collection exists with database prefix

      iex> ArangoXEcto.collection_exists?(Repo, "test", "tenant1")
      true
  """
  @spec collection_exists?(
          Ecto.Repo.t(),
          binary() | atom(),
          atom() | integer(),
          Keyword.t()
        ) ::
          boolean()
  def collection_exists?(repo, collection_name, type \\ :document, opts \\ [])
      when is_binary(collection_name) or is_atom(collection_name) do
    api_query(
      repo,
      :get,
      __build_connection_url__(
        repo,
        "collection/#{collection_name}",
        opts
      ),
      "",
      %{},
      opts
    )
    |> case do
      {:ok, %Arangox.Response{body: %{"isSystem" => false} = body}} ->
        if is_nil(type) do
          true
        else
          Map.get(body, "type") == collection_type_to_integer(type)
        end

      _any ->
        false
    end
  end

  @doc """
  Checks if a view exists

  This will return true if the view exists in the database, otherwise false.

  ## Parameters

  - `repo` - The Ecto repo module to use for the query
  - `view_name` - Name of the collection to check

  ## Examples

  Checking a document collection exists

      iex> ArangoXEcto.view_exists?(Repo, :users_search)
      true
  """
  @spec view_exists?(Ecto.Repo.t(), binary() | atom()) :: boolean()
  def view_exists?(repo, view_name) when is_binary(view_name) or is_atom(view_name) do
    api_query(repo, :get, "/_api/view/#{view_name}")
    |> case do
      {:ok, %Arangox.Response{}} ->
        true

      _any ->
        false
    end
  end

  @doc """
  Returns if a Schema is an edge or not

  Checks for the presence of the `__edge__/0` function on the module.
  """
  @spec edge?(atom()) :: boolean()
  def edge?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__edge__, 0)

  def edge?(_), do: false

  @doc """
  Returns if a Schema is a document schema or not

  Checks for the presence of the `__schema__/1` function on the module and not an edge.
  """
  @spec document?(atom()) :: boolean()
  def document?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
      not edge?(module) and not view?(module)
  end

  def document?(_), do: false

  @doc """
  Returns if a Schema is a view schema or not

  Checks for the presence of the `__view__/1` function on the module.
  """
  @doc since: "1.3.0"
  @spec view?(atom()) :: boolean()
  def view?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__view__, 1)

  def view?(_), do: false

  @doc """
  Returns the type of a module

  This is just a shortcut to using `edge?/1`, `document?/1` and `view?/1`. If it is none of them nil is returned.

  ## Examples

  A real view

      iex> ArangoXEcto.schema_type(MyApp.SomeView)
      :view

  A real edge schema

      iex> ArangoXEcto.schema_type(MyApp.RealEdge)
      :edge

  Some module that is not an Ecto schema

      iex> ArangoXEcto.schema_type(MyApp.RandomModule)
      nil
  """
  @spec schema_type(atom()) :: :document | :edge | nil
  def schema_type(module) do
    cond do
      view?(module) -> :view
      edge?(module) -> :edge
      document?(module) -> :document
      true -> nil
    end
  end

  @doc """
  Same as schema_type/1 but throws an error on none

  This is just a shortcut to using `is_edge/1`, `is_document/1` and `is_view/1`. If it is none of them nil is returned.

  ## Examples

  A real edge schema

      iex> ArangoXEcto.schema_type!(MyApp.RealEdge)
      :edge

  Some module that is not an Ecto schema

      iex> ArangoXEcto.schema_type!(MyApp.RandomModule)
      ** (ArgumentError) Not an Ecto Schema
  """
  @spec schema_type!(atom()) :: :document | :edge
  def schema_type!(module) do
    schema_type(module)
    |> case do
      nil -> raise ArgumentError, "Not an Ecto Schema"
      any -> any
    end
  end

  @doc false
  def __build_connection_url__(repo, string, opts, options \\ "")

  def __build_connection_url__(%{repo: repo}, string, opts, options),
    do: __build_connection_url__(repo, string, opts, options)

  def __build_connection_url__(repo, string, opts, options) do
    database = Adapter.get_database(repo, opts)

    "/_db/#{database}/_api/#{string}#{options}"
  end

  ###############
  ##  Helpers  ##
  ###############

  defp remove_existing_analyzers(repo, analyzers, opts) do
    for %{name: name} <- analyzers do
      ArangoXEcto.api_query(
        repo,
        :delete,
        ArangoXEcto.__build_connection_url__(
          repo,
          "analyzer/#{name}",
          opts,
          "?force=true"
        ),
        "",
        %{},
        opts
      )
    end
  end

  defp add_associations(%{} = loaded, module, %{} = map) when is_atom(module) do
    module.__schema__(:associations)
    |> Enum.reduce(loaded, fn assoc, acc ->
      case Map.fetch(map, Atom.to_string(assoc)) do
        {:ok, map_assoc} ->
          insert_association(acc, assoc, module, map_assoc)

        _ ->
          acc
      end
    end)
  end

  defp insert_association(map, field, module, map_assoc) do
    if Enum.member?(module.__schema__(:associations), field) do
      case module.__schema__(:association, field) do
        %{queryable: assoc_module} ->
          Map.put(map, field, load(map_assoc, assoc_module))

        _ ->
          map
      end
    else
      map
    end
  end

  defp do_create_edge(module, repo, id1, id2, opts) do
    module
    |> validate_ecto_schema()
    |> validate_edge_module()
    |> maybe_create_edges_collection(repo)
    |> ensure_collections_exists!(repo, id1, id2)
    |> edge_changeset(id1, id2, opts)
    |> repo.insert!()
  end

  defp do_delete_all_edges(module, repo, from_id, to_id, opts) do
    collection_name =
      module
      |> validate_ecto_schema()
      |> validate_edge_module()
      |> source_name()

    if collection_exists?(repo, collection_name, :edge) do
      module
      |> find_edge_by_nodes(repo, from_id, to_id, opts)
      |> Enum.each(&repo.delete/1)
    end

    :ok
  end

  defp find_edge_by_nodes(module, repo, from_id, to_id, opts) do
    conditions =
      Keyword.get(opts, :conditions, [])
      |> Keyword.merge(_from: from_id, _to: to_id)

    query =
      from(module,
        where: ^conditions
      )

    repo.all(query)
  end

  defp ensure_collections_exists!(module, repo, id1, id2) do
    collection_from_id(id1)
    |> collection_exists!(repo)

    collection_from_id(id2)
    |> collection_exists!(repo)

    module
  end

  defp collection_exists!(collection_name, repo, type \\ 2) do
    case collection_exists?(repo, collection_name, type) do
      true ->
        true

      false ->
        raise "Collection #{collection_name} does not exist"
    end
  end

  defp collection_from_id(id), do: source_name(id)

  defp create_edge_module(collection_name, from_module, to_module, opts) do
    project_prefix = Module.concat(common_parent_module(from_module, to_module), "Edges")
    module_name = Module.concat(project_prefix, Macro.camelize(collection_name))

    unless Keyword.get(opts, :create, true) == false or
             function_exported?(module_name, :__info__, 1) do
      contents =
        quote do
          use ArangoXEcto.Edge,
            from: unquote(from_module),
            to: unquote(to_module)

          schema unquote(collection_name) do
            edge_fields()
          end
        end

      {:module, _, _, _} = Module.create(module_name, contents, Macro.Env.location(__ENV__))
    end

    module_name
  end

  defp common_parent_module(module1, module2) do
    parent1 = parent_module_list(module1)
    parent2 = parent_module_list(module2)

    common_ordered_list(parent1, parent2)
    |> Module.concat()
  end

  defp parent_module_list(%module{}), do: parent_module_list(module)

  defp parent_module_list(module) do
    Module.split(module)
    |> Enum.drop(-1)
  end

  defp common_ordered_list(list1, list2, acc \\ [])

  defp common_ordered_list([h1 | t1], [h2 | t2], acc) when h1 == h2,
    do: common_ordered_list(t1, t2, [h1 | acc])

  defp common_ordered_list(_, _, acc), do: Enum.reverse(acc)

  defp gen_edge_collection_name(mod1, mod2) do
    name1 = last_mod(mod1)
    name2 = last_mod(mod2)

    sorted_elements = Enum.sort([name1, name2])

    name1 = List.first(sorted_elements) |> String.downcase()
    name2 = List.last(sorted_elements) |> String.downcase()

    "#{name1}_#{name2}"
  end

  defp last_mod(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp source_name(%{} = struct) do
    Map.get(struct.__meta__, :source)
  end

  defp source_name(id) when is_binary(id) do
    String.split(id, "/", trim: true)
    |> List.first()
  end

  defp source_name(module) do
    module.__schema__(:source)
  end

  defp struct_id(%{id: id} = struct) when is_struct(struct) do
    source = source_name(struct)

    "#{source}/#{id}"
  end

  defp struct_id(id) when is_binary(id) do
    case String.match?(id, ~r/[a-zA-Z0-9]+\/[a-zA-Z0-9]+/) do
      true -> id
      false -> raise ArgumentError, "Invalid format for ArangoDB document ID"
    end
  end

  defp struct_id(_), do: raise(ArgumentError, "Invalid struct or _id")

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

  defp edge_changeset(module, id1, id2, opts) do
    attrs =
      Keyword.get(opts, :fields, %{})
      |> Map.merge(%{_from: id1, _to: id2})

    struct = struct(module)

    try do
      Kernel.apply(module, :changeset, [struct, attrs])
    rescue
      UndefinedFunctionError ->
        Edge.edges_changeset(struct, attrs)
    end
  end

  defp maybe_create_edges_collection(schema, repo) do
    unless Keyword.get(repo.config(), :static, true) or
             collection_exists?(repo, source_name(schema), :edge) do
      create_collection(repo, schema)
    end

    schema
  end

  defp maybe_create_collection(repo, schema) when is_atom(repo) or is_pid(repo) do
    type = ArangoXEcto.schema_type!(schema)
    collection_name = schema.__schema__(:source)

    unless ArangoXEcto.collection_exists?(repo, collection_name, type) do
      ArangoXEcto.create_collection(repo, schema)
    end
  end

  defp maybe_create_indexes(_, _, [], _), do: :ok

  defp maybe_create_indexes(repo, collection_name, %{} = indexes, opts),
    do: maybe_create_indexes(repo, collection_name, Map.to_list(indexes), opts)

  defp maybe_create_indexes(repo, collection_name, indexes, opts) when is_list(indexes) do
    Enum.reduce(indexes, nil, fn
      _index, {:error, reason} ->
        {:error, reason}

      index, _acc ->
        {fields, index_opts} = Keyword.pop(index, :fields)

        index_mod = Migration.index(collection_name, fields, index_opts)

        repo.__adapter__().execute_ddl(repo, index_mod, opts)
    end)
  end

  defp maybe_create_indexes(_, _, _, _),
    do: raise("Invalid indexes provided. Should be a list of keyword lists.")

  defp process_vars(query, vars) when is_list(vars),
    do: Enum.reduce(vars, {query, []}, &process_vars(&2, &1))

  defp process_vars({query, vars}, {key, %Ecto.Query{} = res}) do
    val = ArangoXEcto.Query.all(res)

    {String.replace(query, "@" <> Atom.to_string(key), val), vars}
  end

  defp process_vars({query, vars}, {key, val}),
    do: {query, [{key, dump(val)} | vars]}

  defp patch_map(map) do
    for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
  end

  defp filter_keys_for_struct(map) do
    key = Map.get(map, :_key)

    Map.put(map, :id, key)
    |> Map.drop([:_id, :_rev, :_key])
  end

  defp collection_type_to_integer(:document), do: 2

  defp collection_type_to_integer(:edge), do: 3

  defp collection_type_to_integer(type) when is_integer(type) and type in [2, 3], do: type

  defp collection_type_to_integer(_), do: 2

  defp get_repo_db(repo) when not is_nil(repo) do
    if function_exported?(repo, :__adapter__, 0) do
      repo.config() |> Keyword.get(:database)
    end
  end

  defp dump(list_type) when is_list(list_type), do: Enum.map(list_type, &dump/1)
  defp dump(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp dump(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp dump(%Time{} = dt), do: Time.to_iso8601(dt)
  defp dump(%Date{} = dt), do: Date.to_iso8601(dt)
  defp dump(%Decimal{} = d), do: Decimal.to_string(d)
  defp dump(val), do: val

  defp do_result({:ok, _request, response}), do: {:ok, response}
  defp do_result({:error, exception}), do: {:error, exception}
end
