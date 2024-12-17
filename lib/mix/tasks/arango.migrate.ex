defmodule Mix.Tasks.Arango.Migrate do
  @moduledoc """
  Runs the pending migrations for the given repository.

  Unlike the default `ecto_sql` implementation, these migrations will only be run for repos that use
  the ArangoXEcto.Adapter. This prevents it trying to run ArangoDB migrations on non-ArangoXEcto
  repos. This is particularly useful for when using multiple database providers in one app, e.g.
  ArangoXEcto and PostgreSQL (through `ecto_sql`).

  Migrations are expected at "priv/YOUR_REPO/migrations" directory
  of the current application, where "YOUR_REPO" is the last segment
  in your repository name. For example, the repository `MyApp.Repo`
  will use "priv/repo/migrations". The repository `Whatever.MyRepo`
  will use "priv/my_repo/migrations".

  You can configure a repository to use another directory by specifying
  the `:priv` key under the repository configuration. The "migrations"
  part will be automatically appended to it. For instance, to use
  "priv/custom_repo/migrations":

      config :my_app, MyApp.Repo, priv: "priv/custom_repo"

  This task runs all pending migrations by default. To migrate up to a
  specific version number, supply `--to version_number`. To migrate a
  specific number of times, use `--step n`.

  The repositories to migrate are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since ArangoXEcto tasks can only be executed once, if you need to migrate
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      $ mix arango.migrate
      $ mix arango.migrate -r Custom.Repo
                          
      $ mix arango.migrate -n 3
      $ mix arango.migrate --step 3
                          
      $ mix arango.migrate --to 20080906120000

  ## Command line options

    * `--all` - run all pending migrations

    * `--log-migrations` - log migration commands

    * `--log-migrator` - log the migrator

    * `--log-level` - the level to set for `Logger`. This task
      does not start your application, so whatever level you have configured in
      your config files will not be used. If this is not provided, no level
      will be set, so that if you set it yourself before calling this task
      then this won't interfere. Can be any of the `t:Logger.level/0` levels

    * `--migrations-path` - the path to load the migrations from, defaults to
      `"priv/repo/migrations"`. This option may be given multiple times in which
      case the migrations are loaded from all the given directories and sorted
      as if they were in the same one

    * `--no-compile` - does not compile applications before migrating

    * `--no-deps-check` - does not check dependencies before migrating

    * `--pool-size` - the pool size if the repository is started
      only for the task (defaults to 2)

    * `--prefix` - the prefix to run migrations on

    * `--quiet` - do not log migration commands

    * `-r`, `--repo` - the repo to migrate

    * `--step`, `-n` - run n number of pending migrations

    * `--strict-version-order` - abort when applying a migration with old
      timestamp (otherwise it emits a warning)

    * `--to` - run all migrations up to and including version

    * `--to-exclusive` - run all migrations up to and excluding version
  """

  use Mix.Task

  import Mix.Ecto
  import Mix.ArangoXEcto

  @aliases [
    n: :step,
    r: :repo
  ]

  @switches [
    all: :boolean,
    step: :integer,
    to: :integer,
    to_exclusive: :integer,
    quiet: :boolean,
    prefix: :string,
    pool_size: :integer,
    log_level: :string,
    log_migrations: :boolean,
    log_migrator: :boolean,
    strict_version_order: :boolean,
    repo: [:keep, :string],
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :keep
  ]

  @impl true
  def run(args, migrator \\ &ArangoXEcto.Migrator.run/4) do
    repos = parse_repo(args)
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    opts =
      opts
      |> apply_type_opt()
      |> apply_log_opt()

    if log_level = opts[:log_level] do
      Logger.configure(level: String.to_existing_atom(log_level))
    end

    # Start arangox_ecto explicitly before as we don't need
    # to restart those apps if migrated.
    {:ok, _} = Application.ensure_all_started(:arangox_ecto)

    repos
    |> Stream.map(&ensure_repo(&1, args))
    |> Stream.filter(&(&1.__adapter__() == ArangoXEcto.Adapter))
    |> Enum.each(fn repo ->
      paths = ensure_migrations_paths(repo, opts)
      pool = repo.config()[:pool]

      fun = migrator_func(pool, migrator, paths, opts)

      case ArangoXEcto.Migrator.with_repo(repo, fun, [mode: :temporary] ++ opts) do
        {:ok, _migrated, _apps} ->
          :ok

        {:error, error} ->
          Mix.raise("Could not start repo #{inspect(repo)}, error: #{inspect(error)}")
      end
    end)

    :ok
  end

  defp migrator_func(pool, migrator, paths, opts) do
    if Code.ensure_loaded?(pool) and function_exported?(pool, :unboxed_run, 2) do
      &pool.unboxed_run(&1, fn -> migrator.(&1, paths, :up, opts) end)
    else
      &migrator.(&1, paths, :up, opts)
    end
  end

  defp apply_type_opt(opts) do
    if opts[:to] || opts[:to_exclusive] || opts[:step] || opts[:all],
      do: opts,
      else: Keyword.put(opts, :all, true)
  end

  defp apply_log_opt(opts) do
    if opts[:quiet],
      do: Keyword.merge(opts, log: false, log_migrations: false, log_migrator: false),
      else: opts
  end
end
