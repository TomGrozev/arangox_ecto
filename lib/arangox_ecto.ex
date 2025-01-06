defmodule ArangoXEcto do
  @moduledoc """
  The ArangoDB adapter for Ecto.

  ArangoXEcto is provides the following functionality:

    * Full Ecto compatability

    * ArangoDB anonymous graphs

    * Geographic data

    * ArangoSearch (views) and Analyzers

  The functions in this module are the base functions for interacting with ArangoDB that aren't through Ecto.
  All the Ecto functionality hindges on the functions in this module. For example, queries throuh 
  Ecto will use on the `aql_query/4` function in this module.

  ## Ecto compatibility

  To use the ArangoDB with Ecto you will need to use the `ArangoXEcto.Adapter` module in your repo.

      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: ArangoXEcto.Adapter
      end

  You will also have to set the configuration as below. You can set either static or dynamic mode,
  the default is static mode and the option can be omitted. Find out more in the next section.

      config :my_app, MyApp.Repo,
        database: "my_db",
        endpoints: "http://1.2.3.4:8529",
        username: "my_user,
        password: "my_password",
        static: true

  ### Static or Dynamic Mode
  In addition to default config variables, the `static` boolean config option controls the use of
  migrations. By default the value is `true` and will act as other Ecto adapters whereby migrations
  are needed to create the collections. Any collections that do not exist on insert or query will 
  result in an error being raised.

  If you set it to `false`, then you will operate in dynamic mode, therefore collections that don't
  exist will be created on insert and on query no error will be raised.

  Whether static (default) or dynamic is chosen depends on the database design of the project. 
  For a production setup where lots of control is required, it is recommended to have `static` set 
  to `true`, hence this is the default. Sometimes in dev it can be easier to work in dynamic mode
  for smaller projects, however this can cause database inconsistencies in larger projects.

  ### Schemas

  Instead of using the `Ecto.Schema` module the `ArangoXEcto.Schema` module needs to be used. This
  is to enable the use of a `binary_id` that ArangoDB requires.

      defmodule MyApp.Accounts.User do
        use ArangoXEcto.Schema
        import Ecto.Changeset

        schema "users" do
          field :first_name, :string
          field :last_name, :string

          timestamps()
        end

        @doc false
        def changeset(app, attrs) do
          app
          |> cast(attrs, [:first_name, :last_name])
          |> validate_required([:first_name, :last_name])
        end
      end

  When using dynamic mode you can define `options/1` and `indexes/1` can be optionally called inside
  the schema to set options and indexes to be created in dynamic mode. These options will have no
  effect in static mode.

  For example, if you wanted to use a uuid as the key type and create an index on the email the
  following can be used.

      defmodule MyApp.Accounts.User do
          use ArangoXEcto.Schema
          import Ecto.Changeset

          options [
            keyOptions: %{type: :uuid}
          ]

          indexes [
            [fields: [:email]]
          ]

          schema "users" do
            field :email, :string

            timestamps()
          end

          @doc false
          def changeset(app, attrs) do
            app
            |> cast(attrs, [:first_name, :last_name])
            |> validate_required([:first_name, :last_name])
          end
      end

  Please refer to `ArangoXEcto.Schema` for more information on the available options.

  ### Migrations

  Migrations in ArangoXEcto operate just like in other Ecto adapters. However, ArangoXEcto uses its
  own migration commands to allow for interoperability between databases.

  For example, you might want to create a users collection with an index and use ArangoSearch with a
  custom analyzer to make querying more efficient. The below migration could be used to do just that.

      defmodule MyProject.Repo.Migrations.CreateUsers do
        use ArangoXEcto.Migration

        def change do
          create analyzer(:norm_en, :norm, [:frequency, :position], %{
             locale: "en",
             accent: false,
             case: :lower
           })

          create collection(:users) do
            add :first_name, :string, comment: "first_name column"
            add :last_name, :string
            add :gender, :integer
            add :age, :integer
            add :location, :map

            timestamps()
          end

          create index(:users, [:age])
          create unique_index(:users, [:location])

          create view(:user_search, commitIntervalMsec: 1, consolidationIntervalMsec: 1) do
            add_sort(:created_at, :desc)
            add_sort(:first_name)

            add_store([:first_name, :last_name], :none)

            add_link("users", %Link{
              includeAllFields: true,
              fields: %{
                last_name: %Link{
                  analyzers: [:identity, :norm_en]
                }
              }
            })
          end
        end
      end

  You can find more information about how migrations are implemented in the `ArangoXEcto.Migration`
  module.

  ### Sandbox

  Sandbox for concurrent tests is implemented similar to the implementation in `ecto_sql`. See
  `ArangoXEcto.Sandbox` for more info.

  ## Graphs

  Ecto traditionally is made for relational databases and hence relations between schemas is
  represented in such a way. A graph relation (edges) can be thought of as many-to-many relations in
  the relational database world. When it comes to representing graph relations in Ecto, that is
  exactly how it works in ArangoXEcto.

  To use a graph relation you define an `outgoing` and an `incoming` relation on the two schemas,
  for example the following will create a graph relationship between `User -> UserPost -> Post`.
  The `UserPost` edge module will be created automatically.

      defmodule MyApp.User do
        schema "users" do
          field :first_name, :string
          field :last_name, :string
          
          outgoing :posts, MyApp.Post
        end
      end

      defmodule MyApp.Post do
        schema "posts" do
          field :title, :string
          
          incoming :users, MyApp.User
        end
      end

  Behind the scenes this works very similar to a `many_to_many` relationships but has a few key
  differences. As you may know, in a graph an edge can have multiple different node types that it 
  connects to/from. ArangoXEcto uses a special relation type that is based on the principal of
  many-to-many but modified to allow such relationships.

  For example, you may have a `User` schema that you want to connect to `Post` and `Comment`. You
  may not want to have two seperate relationships (e.g. `:posts` and `:comments`) and want to
  combine it all under one (e.g. `:content`). This is what the ArangoXEcto adapter enables. You can
  read more about this type of relationship below.

  ### Edge Modules

  When in dynamic mode the ArangoXEcto adapter dynamically creates and manages edge collections. 
  Each edge collection will be created as an Ecto schema when they are first used. This means that 
  you don't need to create edge collections manually. When in static mode you need to define edges
  manually.

  The edge module will be created under the closest common parent module of the passed modules
  plus the `Edges` alias. The order of the edge name will always be alphabetical to prevent 
  duplicate edges. For example, if the modules were `MyApp.Apple.User` and `MyApp.Apple.Banana.Post`
  then the edge would be created at `MyApp.Apple.Edges.PostUser`. This assumes that the edge 
  collection name was generated and not explicitly defined, if it was `PostUser` would be replaced 
  with the camel case of that collection name (i.e. `address_people` would be `AddressPeople`).

  ### Multiple edge schemas

  Creating a graph relation that has multiple schemas through the same edge is possible in
  ArangoXEcto. For example, take the following.

  ```mermaid
  graph TD
  User --> edge(UsersContent)
  edge(UsersContent) --> Post
  edge(UsersContent) --> Comment
  ```

  Users can have posts or comments through the same edge. This works because edges can have multiple
  from and to schemas. For example if we were to define the `UsersContent` edge it would look like
  this:

      defmodule MyApp.Edges.UsersContent do
        use ArangoXEcto.Edge,
            from: User,
            to: [Post, Comment]

        schema "users_content" do
          edge_fields()
        end
      end

  We can then define our outgoing definition for the User schema like the following.

      defmodule MyApp.User do
        schema "users" do
          field :first_name, :string
          field :last_name, :string
          
          outgoing(
            :my_content,
            %{
              Post => &Post.changeset/2,
              Comment => &Comment.changeset/2
            },
            edge: ArangoXEcto.Edges.UsersContents
          )
        end
      end

  The definition of outgoing here is slightly different from above. Instead of specifying a single
  schema module we specify a map where the keys are schema modules and the values are a list of
  field names to check if it exists in a result to match it with the module. This is an OR
  condition, so if you had `[:a, :b]` that would mean if a result had `:a` it would match or if it
  had `:b` it would match. If a result had both it would match.

  Notice that the edge here was explicitly defined. This is not necessary if you aren't doing
  anything custom on the edge and not including this would just generate an edge like the one
  above.

  #### Preloading

  Due to how graph relations work the regular `c:Ecto.Repo.preload/3` function will only return maps
  instead of structs. If you want to preload the structs you can use the `ArangoXEcto.preload/4`
  function.

      iex> Repo.all(User) |> ArangoXEcto.preload(Repo, [:my_content])
      [%User{id: 123, my_content: [%Post{...}, %Comment{...}]}]

  ## Geodata

  GeoJSON is supported through the `Geo` module and a handy wrapper is provided in the
  `ArangoXEcto.GeoData` module. This module will just verify and create Geo structs that can then be
  used in geojson fields. The `ArangoXEcto.Types.GeoJSON` module defines the GeoJSON type that can
  be used when defining fields, for example below.

      schema "users" do
        field :location, ArangoXEcto.Types.GeoJSON
      end

  You can define a geoJson index on the field using either migrations or dynamic index creation.

      # Migration
      create index(:users, [:location], type: :geo, geoJson: true)

      # Dynamic creation
      indexes [
        [fields: [:location], type: :geo, geoJson: true]
      ]

  You can use `Geo` structs to query the database.

  ## ArangoSearch

  ArangoDB uses ArangoSearch to index collections to improve the searchability of them. With this
  you can do things like have multiple collections in one "view". A view is a concept that is
  essentially take one or more collections and indexes it using whatever "analyzer(s)" you choose to
  apply.

  To query a View you just use it as if you were using any other collection schema. It will return
  the results the same as if you were querying that schema.

  To create a View it is very similar to how you create a collection schema. The following will
  create a view that has primary sorts on :created_at and :name, it will store the :email and the
  :first_name & :last_name fields. Most importantly it will create a link to the `MyApp.Users`
  schema and set the analyzer for the `:name` field to `:text_en`. Some options can be set also.

    defmodule MyApp.UserSearch do
      use ArangoXEcto.View

      alias ArangoXEcto.View.Link

      view "user_search" do
        primary_sort :created_at, :desc
        primary_sort :name

        store_value [:email], :lz4
        store_value [:first_name, :last_name], :none

        link MyApp.Users, %Link{
          includeAllFields: true,
          fields: %{
            name: %Link{
              analyzers: [:text_en]
            }
          }
        }

        options  [
          primarySortCompression: :lz4
        ]
      end
    end

  Querying is done exactly the same as a normal schema except the result will not be a struct.

      iex> Repo.all(MyApp.UsersView)
      [%{first_name: "John", last_name: "Smith"}, _]

  You can find out more info in the `ArangoXEcto.View` module.

  To query using the search function you can use the `ArangoXEcto.Query.search/3` and
  `ArangoXEcto.Query.or_search/3` functions. For example, if we wanted to search using the text
  analyzer we could do the following.

      import ArangoXEcto.Query

      from(UsersView)
      |> search([uv], fragment("ANALYZER(? == ?, \\"text_en\\")", uv.first_name, "John"))
      |> Repo.all()

  ## Mix Tasks

  ArangoXEcto supplies multiple mix tasks for use with migrations. They are:

    * `mix arango.migrate` - Runs forward through migrations
    * `mix arango.rollback` - Rolls back migrations
    * `mix arango.gen.migration` - Generates a migration file

  More information on their usage can be found in their various documentation.
  """

  import Ecto.Query, only: [from: 2]

  alias ArangoXEcto.Adapter
  alias ArangoXEcto.Behaviour.Transaction
  alias ArangoXEcto.Edge
  alias ArangoXEcto.Migration
  alias Ecto.Repo.Preloader

  @type query :: binary()
  @type vars :: keyword() | map()

  @doc """
  Runs a raw AQL query on the database.

  This will create a transaction and cursor on Arango and run the raw query.

  If there is an error in the query such as a syntax error, an `Arangox.Error` will be raised.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `query` - The AQL query string to execute
    * `vars` - A keyword list or a map with the values for variables in the query
    * `opts` - Options to be passed for the transaction

  ## Options

  Accepts any of the options accepted by DBConnection.transaction/3, as well as any of the following:

    * :prefix - The prefix to use for the database. Defaults to the repo database.
    * :read - An array of collection names or a single collection name as a binary to mark as read-only.
    * :write - An array of collection names or a single collection name as a binary to mark as writable. If not set then no writes will be stored.
    * :exclusive - An array of collection names or a single collection name as a binary.
    * :properties - A list or map of additional body attributes to append to the request body when beginning a transaction.

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
          {:ok, {non_neg_integer(), list(map())}} | {:error, any()}
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
          {non_neg_integer(), list(map())}
  def aql_query!(repo_or_meta, query, vars \\ [], opts \\ []) do
    case aql_query(repo_or_meta, query, vars, opts) do
      {:ok, res} -> res
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs an Arangox function using a repo

  This is simply a helper function that extracts the connection from the repo and runs a regular 
  query. It is mainly for internal use but since it can be useful for some custom usecases it is
  included in the documentation.

  ## Parameters

    * `repo` - The Ecto repo module used for connection
    * `function` - An atom of the Arangox function to run
    * `path` - The path of the query
    * `body` - The body of the request
    * `headers` - The headers of the request
    * `opts` - The last opts arg passed to the function

  ## Supported Functions

    * `:abort`
    * `:cursor`
    * `:delete`
    * `:delete!`
    * `:get`
    * `:get!`
    * `:head`
    * `:head!`
    * `:options`
    * `:options!`
    * `:patch`
    * `:patch!`
    * `:post`
    * `:post!`
    * `:put`
    * `:put!`
    * `:request`
    * `:request!`
    * `:run`
    * `:status`
    * `:transaction` (use built in `c:Ecto.Repo.transaction/2` instead)

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

  If in dynamic mode, the edge collection will be created dynamically if no additional fields are
  required, otherwise an edge schema needs to be specified.

  Either an edge module or a collection name is required to create the edge, otherwise one will be
  generated automatically using the from and two schemas.

  The order of the `from` and `to` matters. A changeset validation error will be raised if
  the `from` is not defined in the `from` definition of a provided edge. The same goes for the `to`.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `from` - The Ecto Schema struct to use for the from vertex
    * `to` - The Ecto Schema struct to use for the to vertex
    * `opts` - Options to use

  ## Options

  Accepts the following options:

    * `:edge` - A specific edge module to use for the edge. This is required for any additional fields on the edge. Overrides `collection_name`.
    * `:collection_name` - The name of the collection to use when generating an edge module.
    * `:fields` - The values of the fields to set on the edge. Requires `edge` to be set otherwise it is ignored.

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
  @spec create_edge(Ecto.Repo.t(), struct(), struct(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def create_edge(repo, from, to, opts \\ []) when is_struct(from) and is_struct(to) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    Keyword.get_lazy(opts, :edge, fn -> edge_module(from.__struct__, to.__struct__, opts) end)
    |> do_create_edge(repo, from_id, to_id, opts)
  end

  @doc """
  Creates a view defined by some view schema

  This function is only to be used in dynamic mode and will raise an error if called in static mode.
  Instead use migrations if in static mode.

  This will automatically create analyzers and linked collections. For the analyzers to be 
  automatically created the analyzers module needs to be passed as an option into the view
  module definition. See `ArangoXEcto.View` for more info.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `view` - The View Schema to be created
    * `opts` - Additional options to use for analyzer creation

  ## Options

    * `:prefix` - The prefix for the tenant to create analyzers for

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

    if Keyword.get(repo.config(), :static, true) do
      raise("This function cannot be called in static mode. Please use migrations instead.")
    end

    analyzer_module = view.__analyzer_module__()

    # create the analyzers
    unless is_nil(analyzer_module) do
      create_analyzers(repo, analyzer_module, opts)
    end

    # Create link collections if they don't exist
    view.__view__(:links)
    |> Enum.each(fn {collection, _} ->
      maybe_create_collection(repo, collection)
    end)

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

  This function is only to be used in dynamic mode and will raise an error if called in static mode.
  Instead use migrations if in static mode.

  When operating in dynamic mode the analyzers are automatically created on view create,
  see `ArangoXEcto.create_view/2` for more info.

  This will first force delete any analyzers with the same name before creating
  the ones defined.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `analyzer_module` - The Analyzer module
    * `opts` - Additional options to use for analyzer creation

  ## Options

    * `:prefix` - The prefix for the tenant to create analyzers for

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
    if Keyword.get(repo.config(), :static, true) do
      raise("This function cannot be called in static mode. Please use migrations instead.")
    end

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

  This function is only to be used in dynamic mode and will raise an error if called in static mode.
  Instead use migrations if in static mode.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `schema` - The Collection Schema to be created
    * `opts` - Additional options to pass

  ## Options 

    * `:prefix` - The prefix to use for database tenant collection creation

  ## Examples

      iex> ArangoXEcto.create_collection(Repo, MyApp.Users)
      :ok

  If there is an error in the schema

      iex> ArangoXEcto.create_collection(Repo, MyApp.Users)
      {:error, %Arangox.Error{}}

  """
  @spec create_collection(Ecto.Repo.t(), Ecto.Schema.t(), Keyword.t()) ::
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
  Preloads all associations on the given struct or structs.

  This is similar to `c:Ecto.Repo.preload/3` except it loads graph associations. It functions the same
  as `c:Ecto.Repo.preload/3` but has a slight syntax change.

  This is needed because graph associations use a fake relation module to simulate the required
  behaviour. This means that due to a check in Ecto preloads, it won't match the queried structs.
  Therefore this function applies some logic to preload the data properly.

  ## Parameters

    * `structs_or_struct_or_nil` - A singular or list of structs to preload (if nil will return nil)
    * `repo` - the Ecto repo to use
    * `preloads` - the preload fields (see `c:Ecto.Repo.preload/3` for more info)
    * `opts` - the options to use (same as `c:Ecto.Repo.preload/3`

  ## Example

      iex> Repo.all(User) |> ArangoXEcto.preload(Repo, [:my_content])
      [%User{id: 123, my_content: [%Post{...}, %Comment{...}]}]
  """
  @spec preload(structs_or_struct_or_nil, Ecto.Repo.t(), preloads :: term, opts :: Keyword.t()) ::
          structs_or_struct_or_nil
        when structs_or_struct_or_nil: [Ecto.Schema.t()] | Ecto.Schema.t() | nil
  def preload(struct_or_structs_or_nil, repo, preloads, opts \\ []) do
    repo = repo.get_dynamic_repo()

    Preloader.preload(
      struct_or_structs_or_nil,
      repo,
      preloads,
      Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(repo, :preload, opts))
    )
    |> load_preload(repo)
  end

  defp prepare_opts(repo, operation_name, []), do: repo.default_options(operation_name)

  defp prepare_opts(repo, operation_name, [{key, _} | _rest] = opts) when is_atom(key) do
    operation_name
    |> repo.default_options()
    |> Keyword.merge(opts)
  end

  defp load_preload(structs, repo) when is_list(structs),
    do: Enum.map(structs, &load_struct(&1, repo))

  defp load_preload(struct, repo) when is_map(struct), do: load_struct(struct, repo)

  defp load_struct(struct, repo) do
    schema = struct.__struct__

    schema.__schema__(:associations)
    |> Stream.map(&schema.__schema__(:association, &1))
    |> Stream.filter(&(&1.__struct__ == ArangoXEcto.Association.Graph))
    |> Stream.map(&{&1, Map.get(struct, &1.field)})
    |> Stream.reject(&match?(%Ecto.Association.NotLoaded{}, elem(&1, 1)))
    |> Enum.reduce(struct, fn {assoc, values}, s ->
      values
      |> Stream.map(fn value ->
        [source, _] = String.split(value._id, "/", parts: 2, trim: true)

        {Enum.find(assoc.queryables, &(&1.__schema__(:source) == source)), value}
      end)
      |> Stream.reject(&is_nil/1)
      |> Enum.map(fn {inner_schema, attrs} ->
        fields =
          inner_schema.__schema__(:fields)
          |> Enum.map(&inner_schema.__schema__(:field_source, &1))

        map = Map.take(attrs, fields)

        repo.load(inner_schema, map)
      end)
      |> then(&Map.put(s, assoc.field, &1))
    end)
  end

  @doc """
  Deletes all edges matching matching the query

  If the `:conditions` option is set then those conditions must be true to delete.

  To just delete one edge do so like any other Ecto Schema struct, i.e. using `Ecto.Repo` methods.

  ## Parameters

    * `repo` - The Ecto repo module to use for queries
    * `from` - The Ecto Schema struct to use for the from vertex
    * `to` - The Ecto Schema struct to use for the to vertex
    * `opts` - Options to use

  ## Options

    * `:edge` - A specific edge module to use for the edge. Overrides `:collection_name`.
    * `:collection_name` - The name of the collection to use.
    * `:conditions` - A keyword list of conditions to filter for edge deletion

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
  @spec delete_all_edges(Ecto.Repo.t(), struct(), struct(), Keyword.t()) :: :ok
  def delete_all_edges(repo, from, to, opts \\ []) when is_struct(from) and is_struct(to) do
    from_id = struct_id(from)
    to_id = struct_id(to)

    Keyword.get_lazy(opts, :edge, fn ->
      edge_module(from.__struct__, to.__struct__, Keyword.put(opts, :create, false))
    end)
    |> do_delete_all_edges(repo, from_id, to_id, opts)
  end

  @doc """
  Gets an ID from a schema struct

  If the struct has been queried from the database it will have the `:__id__` field with the id
  which is used. Otherwise it is generated using the schema name and the id (the `_key`).

  ## Parameters

    * `struct` - The Ecto struct

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

    * `module` - Module to get the collection name from
    * `key` - The `_key` to use in the id

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
  Loads raw map into Ecto structs

  Uses `c:Ecto.Repo.load/2` to load a deep map result into Ecto structs.

  If a list of maps are passed then the maps are enumerated over.

  A list of modules can also be passes for possible types. The `_id`
  field is used to check against the module schemas. This is especially
  useful for querying against Arango views where there may be multiple
  schema results returned.

  If a module is passed that isn't a Ecto Schema then an error will be
  raised.

  ## Parameters

    * `maps` - List of maps or singular map to convert to a struct
    * `module` - Module(s) to use for the struct

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
  def load(map, module) when is_list(map),
    do: Enum.map(map, &load(&1, module))

  def load(%{"_id" => id} = map, modules) do
    module = get_module(modules, id)

    Ecto.Repo.Schema.load(ArangoXEcto.Adapter, module, map)
    |> add_associations(module, map)
  end

  def load(%{__id__: id} = map, modules) do
    module = get_module(modules, id)

    struct(module, map)
    |> add_associations(module, map)
  end

  def load(_, _), do: raise(ArgumentError, "Invalid input map or module")

  defp get_module(modules, id) do
    [source, _key] = String.split(id, "/")

    modules
    |> List.wrap()
    |> Stream.map(fn
      {mod, _} -> mod
      mod -> mod
    end)
    |> Enum.find(fn mod ->
      schema_type!(mod)

      mod.__schema__(:source) == source
    end)
  end

  @doc """
  Generates an edge schema dynamically

  If a collection name is not provided one will be dynamically generated. The naming convention
  is the names of the modules in alphabetical order. E.g. `User` and `Post` will combine for a collection
  name of `posts_users` (uses the collection names of the modules) and an edge module name of `PostUser`. 
  This order is used to prevent duplicates if the from and to orders are switched.

  You can also use a list of from and to modules, e.g. from: User, to: [Post, Comment], would result
  in a module name of CommentPostUser and a collection name of comments_posts_users. This may not
  always be an optimal naming convention so it is generally a good idea to make your own edge collection.

  This will create the Ecto Module in the environment dynamically. It will create it under the closest
  common parent module of the passed modules plus the `Edges` alias. For example, if the modules were
  `MyApp.Apple.User` and `MyApp.Apple.Banana.Post` then the edge would be created at `MyApp.Apple.Edges.PostUser`.

  Returns the Edge Module name as an atom.

  ## Parameters

    * `from_modules` - Ecto Schema modules for the from part of the edge
    * `to_modules` - Ecto Schema modules for the to part of the edge
    * `opts` - Options passed for module generation

  ## Options

    * `:collection_name` - The name of collection to use instead of generating it

  ## Examples

      iex> ArangoXEcto.edge_module(MyProject.User, MyProject.Company, [collection_name: "works_for"])
      MyProject.Edges.WorksFor

      iex> ArangoXEcto.edge_module(MyProject.User, [MyProject.Company, MyProject.Group])
      MyProject.Edges.CompanyGroupUser
  """
  @spec edge_module(module() | [module()], module() | [module()], Keyword.t()) :: atom()
  def edge_module(from_modules, to_modules, opts \\ []) do
    from_modules = List.wrap(from_modules)
    to_modules = List.wrap(to_modules)

    collection_name =
      case Keyword.fetch(opts, :collection_name) do
        {:ok, name} -> name
        :error -> gen_edge_collection_name(from_modules, to_modules)
      end

    create_edge_module(collection_name, from_modules, to_modules, opts)
  end

  @doc """
  Returns the name of a database for prefix

  This simply prepends the tenant name to the database supplied in the repo config.

  ## Parameters

    * `repo` - The Ecto repo module to use for the query
    * `prefix` - The prefix to get the database name for
  """
  @spec get_prefix_database(Ecto.Repo.t(), String.t() | atom()) :: String.t()
  def get_prefix_database(repo, nil), do: get_repo_db(repo)
  def get_prefix_database(repo, prefix), do: "#{prefix}_" <> get_repo_db(repo)

  @doc """
  Checks if a collection exists

  This will return true if the collection exists in the database, matches the specified type and is not a system
  database, otherwise it will be false.

  ## Parameters

    * `repo` - The Ecto repo module to use for the query
    * `collection_name` - Name of the collection to check
    * `type` - The type of collection to check against, defaults to a regular document
    * `opts` - Options to be used, available options shown below, defaults to none

  ## Options

    * `:prefix` - The prefix to use for database collection checking

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
  @spec collection_exists?(Ecto.Repo.t(), binary() | atom(), atom() | integer(), Keyword.t()) ::
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

    * `repo` - The Ecto repo module to use for the query
    * `view_name` - Name of the collection to check

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
  Returns true if a Schema is an edge

  Checks for the presence of the `__edge__/0` function on the module.

  ## Parameters

    * `module` - the module to check
  """
  @spec edge?(atom()) :: boolean()
  def edge?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__edge__, 0)

  def edge?(_), do: false

  @doc """
  Returns true if a Schema is a document schema

  Checks for the presence of the `__schema__/1` function on the module and not an edge.

  ## Parameters

    * `module` - the module to check
  """
  @spec document?(atom()) :: boolean()
  def document?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
      not edge?(module) and not view?(module)
  end

  def document?(_), do: false

  @doc """
  Returns true if a Schema is a view schema

  Checks for the presence of the `__view__/1` function on the module.

  ## Parameters

    * `module` - the module to check
  """
  @doc since: "1.3.0"
  @spec view?(atom()) :: boolean()
  def view?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__view__, 1)

  def view?(_), do: false

  @doc """
  Returns the type of a module

  This is just a shortcut to using `edge?/1`, `document?/1` and `view?/1`. If it is none of them nil is returned.

  ## Parameters

    * `module` - the module to check

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

  ## Parameters

    * `module` - the module to check

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

        %{queryables: assoc_modules} ->
          Map.put(map, field, load(map_assoc, assoc_modules))

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

  defp create_edge_module(collection_name, from_modules, to_modules, opts) do
    common_parent = common_parent_module(from_modules, to_modules)
    project_prefix = Module.concat(common_parent, "Edges")
    module_name = Module.concat(project_prefix, Macro.camelize(collection_name))

    if Keyword.get(opts, :create, true) and not function_exported?(module_name, :__info__, 1) do
      contents =
        quote do
          use ArangoXEcto.Edge,
            from: unquote(from_modules),
            to: unquote(to_modules)

          schema unquote(collection_name) do
            edge_fields()
          end
        end

      {:module, _, _, _} = Module.create(module_name, contents, Macro.Env.location(__ENV__))
    end

    module_name
  end

  defp common_parent_module(modules1, modules2) do
    List.flatten(modules1, modules2)
    |> Stream.map(&parent_module_list/1)
    |> Stream.zip()
    |> Stream.map(&Tuple.to_list/1)
    |> Stream.map(&Enum.uniq/1)
    |> Stream.take_while(&match?([_], &1))
    |> Enum.flat_map(&Function.identity/1)
    |> Module.concat()
  end

  defp parent_module_list(%module{}), do: parent_module_list(module)

  defp parent_module_list(module) do
    Module.split(module)
    |> Enum.drop(-1)
  end

  defp gen_edge_collection_name(mod1, mod2) do
    List.flatten(mod1, mod2)
    |> Stream.map(&last_mod/1)
    |> Stream.map(&String.downcase/1)
    |> Enum.sort()
    |> Enum.join("_")
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

  defp struct_id(%{__id__: id}) when not is_nil(id), do: id

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
    |> validate_edge_ids()
  end

  defp validate_edge_ids(changeset) do
    edge_module = changeset.data.__struct__

    changeset
    |> validate_edge_field(edge_module, :_from, :from)
    |> validate_edge_field(edge_module, :_to, :to)
  end

  defp validate_edge_field(changeset, edge_module, key, field) do
    Ecto.Changeset.validate_change(changeset, key, fn ^key, field_val ->
      [source, _] = String.split(field_val, "/", parts: 2)
      related = edge_module.__schema__(:association, field).related
      sources = Enum.map(related, &source_name/1)

      if source in sources do
        []
      else
        [
          {key,
           "#{field} schema is not in the available #{field} schemas for the edge #{edge_module}"}
        ]
      end
    end)
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
