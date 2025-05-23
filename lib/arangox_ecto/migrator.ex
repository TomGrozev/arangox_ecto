defmodule ArangoXEcto.Migrator do
  @moduledoc """
  Lower level API for managing migrations.

  This module provides functions to manage migrations.
  The tasks mentioned below are provided to cover the
  general use cases but it may be necessary to use the
  lower level API in some cases. For example, when building
  an Elixir release, Mix is not available, so this module 
  provides the functions needed to migrate the system.

  Large parts of this module is based on the `ecto_sql` `Migrator`
  module, so a lot of credit to them.

  ## Mix tasks
  The following mix tasks are available. They are similar to `ecto_sql`
  tasks but are appended with `.arango` to allow for both `ecto_sql`
  and `arangox_ecto` to be used side by side.

    * `mix arango.migrate` - migrates an arango repository
    * `mix arango.rollback` - rolls back a particular migration
    * `mix arango.gen.migration` - generates a migration file

  ## Example: Running an individual migration

  Imagine you have this migration:

      defmodule MyApp.MigrationExample do
        use ArangoXEcto.Migration

        def up do
          create collection("my_collection")
        end

        def down do
          drop collection("my_collection")
        end
      end

  You can execute it manually with:

      ArangoXEcto.Migrator.up(Repo, 20240101120000, MyApp.MigrationExample)

  ## Example: Running migrations in a release

  Elixir v1.9 introduces `mix release`, which generates a self-contained
  directory that consists of your application code, all of its dependencies,
  plus the whole Erlang Virtual Machine (VM) and runtime.

  When a release is assembled, Mix is no longer available inside a release
  and therefore none of the Mix tasks. Users may still need a mechanism to
  migrate their databases. This can be achieved with using this `ArangoXEcto.Migrator`
  module:

      defmodule MyApp.Release do
        @app :my_app

        def migrate do
          for repo <- repos() do
            {:ok, _, _} = ArangoXEcto.Migrator.with_repo(repo, &ArangoXEcto.Migrator.run(&1, :up, all: true))
          end
        end

        def rollback(repo, version) do
          {:ok, _, _} = ArangoXEcto.Migrator.with_repo(repo, &ArangoXEcto.Migrator.run(&1, :down, to: version))
        end

        defp repos do
          Application.load(@app)
          Application.fetch_env!(@app, :ecto_repos)
        end
      end

  The example above uses `with_repo/3` to make sure the repository is
  started and then runs all migrations up or a given migration down.
  Note you will have to replace `MyApp` and `:my_app` on the first two
  lines by your actual application name. Once the file above is added
  to your application, you can assemble a new release and invoke the
  commands above in the release root like this:

      $ bin/my_app eval "MyApp.Release.migrate"
      $ bin/my_app eval "MyApp.Release.rollback(MyApp.Repo, 20231225190000)"

  ## Example: Running migrations on application startup

  Add the following to the top of your application child spec:

      {ArangoXEcto.Migrator, 
        repos: Application.fetch_env!(:my_app, :ecto_repos), 
        skip: System.get_env("SKIP_MIGRATIONS") == "true")}

  This will allow you to use the environment variable `SKIP_MIGRATIONS` to skip running the
  migrations on startup.

  Additionally, the other options specified in `up/4` can be passed. For example, if you wanted to
  log the migrations and run them in a specific prefix you could do the following:

      {ArangoXEcto.Migrator, 
        repos: Application.fetch_env!(:my_app, :ecto_repos), 
        log_migrator: true,
        prefix: "super_cool_user"}

  Rolling back would be done normally using the `mix arango.rollback` mix task.
  """
  @moduledoc since: "2.0.0"

  use GenServer

  require Logger

  alias ArangoXEcto.View.Link
  alias ArangoXEcto.Migration.{Runner, SchemaMigration}
  alias ArangoXEcto.Migration.{Analyzer, Collection, Index, JsonSchema, View}

  @type command :: :create | :create_if_not_exists | :drop | :drop_if_exists
  @type subcommand :: :add | :add_enum | :rename
  @type log :: {Logger.level(), Logger.message(), Logger.metadata()}

  @doc """
  Runs migrations as part of your supervision tree.

  ## Options

    * `:repos` - Required option to tell the migrator which Repo's to
      migrate. Example: `repos: [MyApp.Repo]`

    * `:skip` - Option to skip migrations. Defaults to `false`.

  Plus all other options described in `up/4`.

  See "Example: Running migrations on application startup" for more info.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {repos, opts} = Keyword.pop!(opts, :repos)
    {skip?, opts} = Keyword.pop(opts, :skip, false)
    {migrator, opts} = Keyword.pop(opts, :migrator, &ArangoXEcto.Migrator.run/3)
    opts = Keyword.put(opts, :all, true)

    if !skip? do
      for repo <- repos do
        {:ok, _, _} = with_repo(repo, &migrator.(&1, :up, opts))
      end
    end

    :ignore
  end

  @doc """
  Ensures the repo is started to perform migration operations.

  All applications required to run the repo will be started before
  with the chosen mode. If the repo has not yet been started,
  it is manually started, with a `:pool_size` of 2 (or otherwise passed),
  before the given function is executed, and the repo is then terminated.
  If the repo was already started, then the function is directly executed,
  without terminating the repo afterwards.

  Although this function was designed to start repositories for running
  migrations, it can be used by any code, Mix task, or release tooling
  that needs to briefly start a repository to perform a certain operation
  and then terminate.

  The repo may also configure a `:start_apps_before_migration` option
  which is a list of applications to be started before the migration
  runs.

  It returns `{:ok, fun_return, apps}`, with all apps that have been
  started, or `{:error, term}`.

  ## Options

    * `:pool_size` - The pool size to start the repo for migrations.
      Defaults to 2.
    * `:mode` - The mode to start all applications.
      Defaults to `:permanent`.

  ## Examples

      {:ok, _, _} =
        ArangoXEcto.Migrator.with_repo(repo, fn repo ->
          ArangoXEcto.Migrator.run(repo, :up, all: true)
        end)

  """
  @spec with_repo(repo :: Ecto.Repo.t(), fun :: function(), opts :: Keyword.t()) ::
          {:ok, any(), list()} | {:error, any()}
  def with_repo(repo, fun, opts \\ []) do
    config = repo.config()
    mode = Keyword.get(opts, :mode, :permanent)
    apps = [:arangox_ecto | config[:start_apps_before_migration] || []]

    extra_started =
      Enum.flat_map(apps, fn app ->
        {:ok, started} = Application.ensure_all_started(app, mode)
        started
      end)

    {:ok, repo_started} = repo.__adapter__().ensure_all_started(config, mode)
    started = extra_started ++ repo_started
    pool_size = Keyword.get(opts, :pool_size, 2)
    migration_repo = config[:migration_repo] || repo

    case ensure_repo_started(repo, pool_size) do
      {:ok, repo_after} ->
        case ensure_migration_repo_started(migration_repo, repo) do
          {:ok, migration_repo_after} ->
            try do
              {:ok, fun.(repo), started}
            after
              after_action(repo, repo_after)
              after_action(migration_repo, migration_repo_after)
            end

          {:error, _} = error ->
            after_action(repo, repo_after)
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the migrations path for a repository.

  Accepts a second option allowing to specify the name of / path to the 
  directory for the migrations.
  """
  @spec migrations_path(repo :: Ecto.Repo.t(), directory :: String.t()) :: String.t()
  def migrations_path(repo, directory \\ "migrations") do
    config = repo.config()
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()
    priv = config[:priv] || "priv/#{repo_name}"
    app = Keyword.fetch!(config, :otp_app)

    Application.app_dir(app, Path.join(priv, directory))
  end

  @doc """
  Gets all migrated versions.

  Ensures the migrations collection exists if it doesn't exist yet.

  ## Options 

    * `:prefix` - the prefix to run the migrations on
    * `:dynamic_repo` - the name of the Repo supervisor process.
      See `c:Ecto.Repo.put_dynamic_repo/1`.
    * `:skip_collection_creation` - skips any attempt to create the migration collection
      Useful for situations where user needs to check migrations but has
      insufficient permissions to create the collection.  Note that migrations
      commands may fail if this is set to true. Defaults to `false`.  Accepts a
      boolean.
  """
  @spec migrated_versions(repo :: Ecto.Repo.t(), opts :: Keyword.t()) :: [integer()]
  def migrated_versions(repo, opts \\ []) do
    ensure_migrations_collection(repo, opts, fn _config, versions -> versions end)
  end

  @doc """
  Runs an up migration on a given repo.

  ## Options 
    
    * `:log` - the level to use for logging of migration instructions.
      Defaults to `:info`. Can be any of `Logger.level/0` values or a boolean.
      If `false`, it also avoids logging messages from the database.
    * `:log_migrations` - the level to use for logging of ArangoDB commands
      generated by migrations. Can be any of the `Logger.level/0` values
      or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:log_migrator` - the level to use for logging of ArangoDB commands emitted
      by the migrator, such as transactions, locks, etc. Can be any of the `Logger.level/0`
      values or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:prefix` - the prefix to run the migrations on
    * `:dynamic_repo` - the name of the Repo supervisor process.
      See `c:Ecto.Repo.put_dynamic_repo/1`.
    * `:strict_version_order` - abort when applying a migration with old timestamp
      (otherwise it emits a warning)
  """
  @spec up(Ecto.Repo.t(), integer(), module(), Keyword.t()) :: :ok | :already_up
  def up(repo, version, module, opts \\ []) do
    ensure_migrations_collection(repo, opts, fn config, versions ->
      if version in versions do
        :already_up
      else
        result = do_up(repo, config, version, module, opts)

        check_newer_migration(version, versions, opts)

        result
      end
    end)
  end

  @doc """
  Runs a down migration on a given repo.

  ## Options 
    
    * `:log` - the level to use for logging of migration instructions.
      Defaults to `:info`. Can be any of `Logger.level/0` values or a boolean.
      If `false`, it also avoids logging messages from the database.
    * `:log_migrations` - the level to use for logging of ArangoDB commands
      generated by migrations. Can be any of the `Logger.level/0` values
      or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:log_migrator` - the level to use for logging of ArangoDB commands emitted
      by the migrator, such as transactions, locks, etc. Can be any of the `Logger.level/0`
      values or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:prefix` - the prefix to run the migrations on
  """
  @spec down(Ecto.Repo.t(), integer(), module(), Keyword.t()) :: :ok | :already_down
  def down(repo, version, module, opts \\ []) do
    ensure_migrations_collection(repo, opts, fn config, versions ->
      if version in versions do
        do_down(repo, config, version, module, opts)
      else
        :already_down
      end
    end)
  end

  @doc """
  Runs migrations for the given repository.

  Equivalent to:

      ArangoXEcto.Migrator.run(repo, [ArangoXEcto.Migrator.migrations_path(repo)], direction, opts)

  See `run/4` for more information.
  """
  @spec run(Ecto.Repo.t(), atom, Keyword.t()) :: [integer]
  def run(repo, direction, opts) do
    run(repo, [migrations_path(repo)], direction, opts)
  end

  @doc ~S"""
  Apply migrations to a repository with a given strategy.

  The second argument identifies where the migrations are sourced from.
  A binary representing directory (or a list of binaries representing
  directories) may be passed, in which case we will load all files
  following the "#{VERSION}_#{NAME}.exs" schema. The `migration_source`
  may also be a list of tuples that identify the version number and
  migration modules to be run, for example:

      ArangoXEcto.Migrator.run(Repo, [{0, MyApp.Migration1}, {1, MyApp.Migration2}, ...], :up, opts)

  A strategy (which is one of `:all`, `:step`, `:to`, or `:to_exclusive`) must be given as
  an option.

  ## Execution model

  In order to run migrations, at least two database connections are
  necessary. One is used to lock the "_migrations" collection and
  the other one to effectively run the migrations. This allows multiple
  nodes to run migrations at the same time, but guarantee that only one
  of them will effectively migrate the database.

  ## Options

    * `:all` - runs all available if `true`

    * `:step` - runs the specific number of migrations

    * `:to` - runs all until the supplied version is reached
      (including the version given in `:to`)

    * `:to_exclusive` - runs all until the supplied version is reached
      (excluding the version given in `:to_exclusive`)

  Plus all other options described in `up/4`.
  """
  @spec run(Ecto.Repo.t(), String.t() | [String.t()] | [{integer, module}], atom, Keyword.t()) ::
          [integer]
  def run(repo, migration_source, direction, opts) do
    migration_source = List.wrap(migration_source)

    pending =
      ensure_migrations_collection(repo, opts, fn _config, versions ->
        cond do
          opts[:all] ->
            pending_all(versions, migration_source, direction)

          to = opts[:to] ->
            pending_to(versions, migration_source, direction, to)

          to_exclusive = opts[:to_exclusive] ->
            pending_to_exclusive(versions, migration_source, direction, to_exclusive)

          step = opts[:step] ->
            pending_step(versions, migration_source, direction, step)

          true ->
            {:error,
             ArgumentError.exception(
               "expected one of :all, :to, :to_exclusive, or :step strategies"
             )}
        end
      end)

    # The collection should have been created now
    opts = Keyword.put(opts, :skip_collection_creation, true)

    ensure_no_duplication!(pending)

    migrate(Enum.map(pending, &load_migration!/1), direction, repo, opts)
  end

  @doc """
  Returns an array of the statuses of migrations for the given repo

  Doesn't actually run the migrations.

  This is a shortcut to

      ArangoXEcto.Migrator.migrations(repo, [ArangoXEcto.Migrator.migrations_path(repo)])

  """
  @spec migrations(Ecto.Repo.t()) :: [{:up | :down, id :: integer(), name :: String.t()}]
  def migrations(repo) do
    migrations(repo, [migrations_path(repo)])
  end

  @doc """
  Returns an array of the statuses of migrations for the given repo

  Doesn't actually run the migrations.
  """
  @spec migrations(Ecto.Repo.t(), String.t() | [String.t()], Keyword.t()) :: [
          {:up | :down, id :: integer(), name :: String.t()}
        ]
  def migrations(repo, directories, opts \\ []) do
    directories = List.wrap(directories)

    repo
    |> migrated_versions(opts)
    |> collect_migrations(directories)
    |> Enum.sort_by(fn {_, version, _} -> version end)
  end

  @creates [:create, :create_if_not_exists]
  @drops [:drop, :drop_if_exists]

  @doc """
  Executes a command on a repo
   
  The commands are passed from the migration module. A command essentially is the action of a
  migration, e.g. create, alter, rename, delete an object.

  `opts` is passed to the database query when the command is run. Available options are dependant on
  the command being executed.

  ## Available Commands

  All commands are either a tuple or a string with AQL which is executed. The first element of the
  tuple is the action to be performed, the second is the object of the action. For some commands
  (such as creation of a collection) there is a third element of the tuple.

  ### Creates (:create and :create_if_not_exists)

  | 2nd element (Object) |              Third element            |
  | -------------------- | ------------------------------------- |
  | Collection           | Field commands passed to `JsonSchema` |
  | Index                |                                       |
  | View                 | View definition commands              |
  | Analyzer             |                                       |

  ### Alter (:alter)

  | 2nd element (Object) |                              Third element                          |
  | -------------------- | ------------------------------------------------------------------- |
  | Existing Collection  | Field commands passed to `JsonSchema` (merged with existing schema) |
  | Existing View        | View definition commands                                            |

  ### Drops (:drop and :drop_if_exists)

  | 2nd element (Object) | Third element |
  | -------------------- | ------------- |
  | Existing Collection  |               |
  | Existing Index       |               |
  | Existing View        |               |
  | Existing Analyzer    |               |

  ### Rename (:rename)

  | 2nd element (Object) |       Third element      |
  | -------------------- | ------------------------ |
  | Existing Collection  | Collection with new name |
  | Existing View        | View with new name       |
  """
  @spec execute_command(
          Ecto.Adapter.adapter_meta(),
          {command(), Collection.t() | Index.t() | View.t() | Analyzer.t(),
           [JsonSchema.command()]},
          Keyword.t()
        ) :: log()
  # Collection
  def execute_command(meta, {command, %Collection{prefix: prefix} = collection, fields}, opts)
      when command in @creates do
    args =
      collection
      |> Map.from_struct()
      |> Map.put(:schema, JsonSchema.generate_schema(fields))
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :post,
      ArangoXEcto.__build_connection_url__(
        meta,
        "collection",
        opts
      ),
      args,
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        {command, %Collection{name: name, prefix: prefix, isSystem: is_system}},
        opts
      )
      when command in @drops do
    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :delete,
      ArangoXEcto.__build_connection_url__(
        meta,
        "collection/#{name}",
        opts,
        "?isSystem=#{is_system}"
      ),
      "",
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        {:alter, %Collection{name: name, prefix: prefix} = collection, columns},
        opts
      ) do
    opts = Keyword.put(opts, :prefix, prefix)

    current_schema = get_current_schema!(meta, collection, opts)

    args =
      collection
      |> Map.from_struct()
      |> Map.put(
        :schema,
        JsonSchema.generate_schema(columns, schema: current_schema)
      )
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    ArangoXEcto.api_query(
      meta,
      :put,
      ArangoXEcto.__build_connection_url__(
        meta,
        "collection/#{name}/properties",
        opts
      ),
      args,
      %{},
      opts
    )
    |> log_execute()
  end

  def execute_command(
        meta,
        {:rename, %Collection{name: current_name, prefix: prefix},
         %Collection{name: new_name, prefix: prefix}},
        opts
      ) do
    args = %{name: new_name}

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :put,
      ArangoXEcto.__build_connection_url__(
        meta,
        "collection/#{current_name}/rename",
        opts
      ),
      args,
      %{},
      opts
    )
    |> log_execute()
  end

  # Index
  def execute_command(
        meta,
        {command, %Index{collection_name: collection_name, prefix: prefix} = index},
        opts
      )
      when command in @creates do
    args =
      index
      |> Map.from_struct()
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :post,
      ArangoXEcto.__build_connection_url__(
        meta,
        "index",
        opts,
        "?collection=#{collection_name}"
      ),
      args,
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        {command, %Index{prefix: prefix} = index},
        opts
      )
      when command in @drops do
    opts = Keyword.put(opts, :prefix, prefix)

    case get_index_id_by_name(meta, index, opts) do
      {:ok, id} ->
        ArangoXEcto.api_query(
          meta,
          :delete,
          ArangoXEcto.__build_connection_url__(
            meta,
            "index/#{id}",
            opts
          ),
          "",
          %{},
          opts
        )

      error ->
        error
    end
    |> process_existing(command)
    |> log_execute()
  end

  # View
  def execute_command(
        meta,
        {command, %View{prefix: prefix} = view, subcommands},
        opts
      )
      when command in @creates do
    view_definition = generate_view_definition(view, subcommands)

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :post,
      ArangoXEcto.__build_connection_url__(meta, "view", opts),
      view_definition,
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        {:alter, %View{name: name, prefix: prefix} = view, subcommands},
        opts
      ) do
    view_definition = generate_view_definition(view, subcommands)

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :patch,
      ArangoXEcto.__build_connection_url__(
        meta,
        "view/#{name}/properties",
        opts
      ),
      view_definition,
      %{},
      opts
    )
    |> log_execute()
  end

  def execute_command(
        meta,
        {:rename, %View{name: current_name, prefix: prefix},
         %View{name: new_name, prefix: prefix}},
        opts
      ) do
    args = %{name: new_name}

    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :put,
      ArangoXEcto.__build_connection_url__(
        meta,
        "view/#{current_name}/rename",
        opts
      ),
      args,
      %{},
      opts
    )
    |> log_execute()
  end

  def execute_command(
        meta,
        {command, %View{name: name, prefix: prefix}},
        opts
      )
      when command in @drops do
    opts = Keyword.put(opts, :prefix, prefix)

    ArangoXEcto.api_query(
      meta,
      :delete,
      ArangoXEcto.__build_connection_url__(meta, "view/#{name}", opts),
      "",
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  # Analyzer
  def execute_command(
        meta,
        {command, %Analyzer{prefix: prefix} = analyzer},
        opts
      )
      when command in @creates do
    opts = Keyword.put(opts, :prefix, prefix)

    url = ArangoXEcto.__build_connection_url__(meta, "analyzer", opts)

    ArangoXEcto.api_query(
      meta,
      :post,
      url,
      Analyzer.definition(analyzer),
      %{},
      opts
    )
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        {command, %Analyzer{name: name, prefix: prefix}},
        opts
      )
      when command in @drops do
    opts = Keyword.put(opts, :prefix, prefix)

    url = ArangoXEcto.__build_connection_url__(meta, "analyzer/#{name}", opts)

    ArangoXEcto.api_query(meta, :delete, url, "", %{}, opts)
    |> process_existing(command)
    |> log_execute()
  end

  def execute_command(
        meta,
        aql,
        opts
      )
      when is_binary(aql) do
    ArangoXEcto.aql_query(meta, aql, [], opts)
    |> log_execute()
  end

  def execute_command(_meta, _command, _opts), do: :ok

  ###########
  # Helpers #
  ###########

  def generate_view_definition(%View{} = view, subcommands) do
    view =
      Map.from_struct(view)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    Enum.reduce(subcommands, view, fn
      {:add_sort, field, direction}, acc ->
        Map.update!(acc, :primarySort, &[%{field: field, direction: direction} | &1])

      {:add_store, fields, compression}, acc ->
        Map.update!(acc, :storedValues, &[%{fields: fields, compression: compression} | &1])

      {:add_link, schema_name, link}, acc ->
        schema_name =
          if is_atom(schema_name) and function_exported?(schema_name, :__schema__, 1) do
            schema_name.__schema__(:source)
          else
            schema_name
          end

        put_in(acc, [:links, schema_name], Link.to_map(link))
    end)
  end

  defp get_index_id_by_name(meta, %Index{collection_name: collection_name, name: name}, opts) do
    ArangoXEcto.api_query(
      meta,
      :get,
      ArangoXEcto.__build_connection_url__(
        meta,
        "index",
        opts,
        "?collection=#{collection_name}"
      ),
      "",
      %{},
      opts
    )
    |> case do
      {:ok, %Arangox.Response{body: %{"indexes" => indexes}}} ->
        Enum.find_value(indexes, {:error, "no index exists"}, fn
          %{"name" => ^name, "id" => id} ->
            {:ok, id}

          _ ->
            nil
        end)

      error ->
        error
    end
  end

  defp get_current_schema!(meta, %Collection{name: name}, opts) do
    ArangoXEcto.api_query(
      meta,
      :get,
      ArangoXEcto.__build_connection_url__(
        meta,
        "collection/#{name}/properties",
        opts
      ),
      "",
      %{},
      opts
    )
    |> case do
      {:ok, %Arangox.Response{body: %{"schema" => schema}}} ->
        schema

      {:error, error} ->
        raise error
    end
  end

  defp process_existing({:error, %Arangox.Error{error_num: 1207}} = error, :create),
    do: error

  defp process_existing({:error, %Arangox.Error{error_num: 1207}}, :create_if_not_exists),
    do: {:ok, "collection already exists"}

  defp process_existing({:error, %Arangox.Error{error_num: 1203}} = error, :drop),
    do: error

  defp process_existing({:error, %Arangox.Error{error_num: 1203}}, :drop_if_exists),
    do: {:ok, "collection already dropped"}

  defp process_existing(res, _command),
    do: res

  defp log_execute({:ok, msg}) when is_binary(msg), do: {:info, msg, []}
  defp log_execute({:ok, _}), do: {:info, "completed successfully", []}
  defp log_execute({:error, %Arangox.Error{message: message}}), do: {:error, message, []}
  defp log_execute({:error, message}), do: {:error, message, []}
  defp log_execute(res), do: res

  defp pending_to(versions, migration_source, direction, target) when is_integer(target) do
    within_target_version? = fn
      {version, _, _}, target, :up -> version <= target
      {version, _, _}, target, :down -> version >= target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&within_target_version?.(&1, target, direction))
  end

  defp pending_to_exclusive(versions, migration_source, direction, target)
       when is_integer(target) do
    within_target_version? = fn
      {version, _, _}, target, :up -> version < target
      {version, _, _}, target, :down -> version > target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&within_target_version?.(&1, target, direction))
  end

  defp pending_step(versions, migration_source, direction, count) do
    pending_in_direction(versions, migration_source, direction)
    |> Enum.take(count)
  end

  defp pending_all(versions, migration_source, direction) do
    pending_in_direction(versions, migration_source, direction)
  end

  defp pending_in_direction(versions, migration_source, :up) do
    migration_source
    |> migrations_for()
    |> Enum.reject(fn {version, _name, _file} -> version in versions end)
  end

  defp pending_in_direction(versions, migration_source, :down) do
    migration_source
    |> migrations_for()
    |> Enum.filter(fn {version, _name, _file} -> version in versions end)
    |> Enum.reverse()
  end

  defp migrations_for(migration_source) when is_list(migration_source) do
    migration_source
    |> Enum.flat_map(fn
      directory when is_binary(directory) ->
        Path.join([directory, "**", "*.exs"])
        |> Path.wildcard()
        |> Enum.map(&extract_migration_info/1)
        |> Enum.filter(& &1)

      {version, module} ->
        [{version, module, module}]
    end)
    |> Enum.sort()
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} ->
        {integer, name, file}

      _ ->
        nil
    end
  end

  defp ensure_no_duplication!([]), do: :ok

  defp ensure_no_duplication!([{version, name, _} | t]) do
    cond do
      List.keyfind(t, version, 0) ->
        raise Ecto.MigrationError,
              "migrations can't be executed, migration version #{version} is duplicated"

      List.keyfind(t, name, 1) ->
        raise Ecto.MigrationError,
              "migrations can't be executed, migration name #{name} is duplicated"

      true ->
        ensure_no_duplication!(t)
    end
  end

  defp check_newer_migration(version, versions, opts) do
    if version != Enum.max([version | versions]) do
      latest = Enum.max(versions)

      message = """
      You are running migration #{version} but an older \
      migration with version #{latest} has already run.

      This can be an issue if you have already ran #{latest} in production \
      because a new deployment may migrate #{version} but a rollback command \
      would revert #{latest} instead of #{version}.

      If this can be an issue, we recommend to rollback #{version} and change \
      it to a version later than #{latest}.
      """

      if opts[:strict_version_order] do
        raise Ecto.MigrationError, message
      else
        Logger.warning(message)
      end
    end
  end

  defp load_migration!({version, _, mod}) when is_atom(mod) do
    if migration?(mod) do
      {version, mod}
    else
      raise Ecto.MigrationError, "module #{inspect(mod)} is not an ArangoXEcto.Migration"
    end
  end

  defp load_migration!({version, _, file}) when is_binary(file) do
    loaded_modules = file |> Code.compile_file() |> Enum.map(&elem(&1, 0))

    if mod = Enum.find(loaded_modules, &migration?/1) do
      {version, mod}
    else
      raise Ecto.MigrationError,
            "file #{Path.relative_to_cwd(file)} is not an ArangoXEcto.Migration"
    end
  end

  defp do_up(repo, config, version, module, opts) do
    async_migrate(repo, config, version, module, :up, opts, fn ->
      attempt(repo, config, version, module, :forward, :up, :up, opts) ||
        attempt(repo, config, version, module, :forward, :change, :up, opts) ||
        {:error,
         Ecto.MigrationError.exception(
           "#{inspect(module)} does not implement a `up/0` or `change/0` function"
         )}
    end)
  end

  defp do_down(repo, config, version, module, opts) do
    async_migrate(repo, config, version, module, :down, opts, fn ->
      attempt(repo, config, version, module, :forward, :down, :down, opts) ||
        attempt(repo, config, version, module, :backward, :change, :down, opts) ||
        {:error,
         Ecto.MigrationError.exception(
           "#{inspect(module)} does not implement a `down/0` or `change/0` function"
         )}
    end)
  end

  defp async_migrate(repo, config, version, module, direction, opts, fun) do
    dynamic_repo = repo.get_dynamic_repo()

    fun_with_status = fn ->
      result = fun.()
      apply(SchemaMigration, direction, [repo, config, version, opts])

      result
    end

    fn -> run_maybe_in_transaction(repo, dynamic_repo, module, fun_with_status, opts) end
    |> Task.async()
    |> Task.await(:infinity)
  end

  defp run_maybe_in_transaction(repo, dynamic_repo, module, fun, opts) do
    repo.put_dynamic_repo(dynamic_repo)

    if module.__migration__()[:disable_ddl_transaction] do
      fun.()
    else
      {_, source} = SchemaMigration.get_repo_and_source(repo, repo.config())

      {:ok, result} =
        repo.transaction(fun, log: migrator_log(opts), timeout: :infinity, write: [source])

      result
    end
  catch
    kind, reason ->
      {kind, reason, __STACKTRACE__}
  end

  defp attempt(repo, config, version, module, direction, operation, reference, opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, operation, 0) do
      Runner.run(repo, config, version, module, direction, operation, reference, opts)
      :ok
    end
  end

  defp migration?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__migration__, 0)
  end

  defp migrate([], direction, _repo, opts) do
    level = Keyword.get(opts, :log, :info)
    log(level, "Migrations already #{direction}")
    []
  end

  defp migrate(migrations, direction, repo, opts) do
    for {version, mod} <- migrations,
        do_direction(direction, repo, version, mod, opts),
        do: version
  end

  defp do_direction(:up, repo, version, mod, opts) do
    ensure_migrations_collection(repo, opts, fn config, versions ->
      if version not in versions do
        do_up(repo, config, version, mod, opts)
      end
    end)
  end

  defp do_direction(:down, repo, version, mod, opts) do
    ensure_migrations_collection(repo, opts, fn config, versions ->
      if version in versions do
        do_down(repo, config, version, mod, opts)
      end
    end)
  end

  defp ensure_repo_started(repo, pool_size) do
    case repo.start_link(pool_size: pool_size) do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :restart}

      {:error, _} = error ->
        error
    end
  end

  defp ensure_migration_repo_started(repo, repo), do: {:ok, :noop}

  defp ensure_migration_repo_started(migration_repo, _repo) do
    case migration_repo.start_link() do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :noop}

      {:error, _} = error ->
        error
    end
  end

  defp after_action(repo, :restart) do
    if Process.whereis(repo) do
      %{pid: pid} = Ecto.Adapter.lookup_meta(repo)
      Supervisor.restart_child(repo, pid)
    end
  end

  defp after_action(repo, :stop), do: repo.stop()

  defp after_action(_repo, :noop), do: :noop

  defp collect_migrations(versions, migration_source) do
    ups_with_file =
      versions
      |> pending_in_direction(migration_source, :down)
      |> Enum.map(fn {version, name, _} -> {:up, version, name} end)

    ups_without_file =
      versions
      |> versions_without_file(migration_source)
      |> Enum.map(fn version -> {:up, version, "** FILE NOT FOUND **"} end)

    downs =
      versions
      |> pending_in_direction(migration_source, :up)
      |> Enum.map(fn {version, name, _} -> {:down, version, name} end)

    ups_with_file ++ ups_without_file ++ downs
  end

  defp versions_without_file(versions, migration_source) do
    versions_with_file =
      migration_source
      |> migrations_for()
      |> Enum.map(fn {version, _, _} -> version end)

    versions -- versions_with_file
  end

  defp ensure_migrations_collection(repo, opts, fun) do
    dynamic_repo = Keyword.get(opts, :dynamic_repo, repo.get_dynamic_repo())
    skip_collection_creation = Keyword.get(opts, :skip_collection_creation, false)
    previous_dynamic_repo = repo.put_dynamic_repo(dynamic_repo)

    try do
      config = repo.config()

      if !skip_collection_creation do
        verbose_schema_migration(repo, "create _migrations collection", fn ->
          SchemaMigration.ensure_schema_migrations_collection!(repo, config, opts)
        end)
      end

      {migration_repo, query, all_opts} = SchemaMigration.versions(repo, config, opts[:prefix])

      case fun.(config, migration_repo.all(query, all_opts)) do
        {kind, reason, stacktrace} ->
          :erlang.raise(kind, reason, stacktrace)

        {:error, error} ->
          raise error

        result ->
          result
      end
    after
      repo.put_dynamic_repo(previous_dynamic_repo)
    end
  end

  defp verbose_schema_migration(repo, reason, fun) do
    fun.()
  rescue
    error ->
      Logger.error("""
      Could not #{reason}. This error usually happens due to the following:

        * The database does not exist
        * The "_migrations" collection, which Ecto uses for managing
          migrations, was defined by another library

      To fix the first issue, run "mix ecto.create" for the desired MIX_ENV.

      To address the second, you can run "mix ecto.drop" followed by
      "mix ecto.create", both for the desired MIX_ENV. Alternatively you may 
      configure Ecto to use another collection and/or repository for managing 
      migrations:

          config #{inspect(repo.config[:otp_app])}, #{inspect(repo)},
            migration_source: "some_other_collection_for_schema_migrations",
            migration_repo: AnotherRepoForSchemaMigrations

      The full error report is shown below.
      """)

      reraise error, __STACKTRACE__
  end

  defp log(false, _msg), do: :ok
  defp log(true, msg), do: Logger.info(msg)
  defp log(level, msg), do: Logger.log(level, msg)

  defp migrator_log(opts) do
    Keyword.get(opts, :log_migrator, false)
  end
end
