defmodule ArangoXEcto.Migration.SchemaMigration do
  # Defines a schema for a collection that tracks schema migrations.
  # The default collection name is `_migrations`.
  @moduledoc false

  use ArangoXEcto.Schema

  alias ArangoXEcto.Migration.Collection

  import Ecto.Query, only: [from: 2]

  @type t :: %__MODULE__{}

  schema "_migrations" do
    field(:version, :integer, primary_key: true)
    timestamps(updated_at: false)
  end

  # The migration flag is used to signal to the repository
  # we are in a migration operation.
  @default_opts [
    timeout: :infinity,
    log: false,
    schema_migration: true,
    telemetry_options: [_migrations: true]
  ]

  @doc """
  Ensures migrations collection exists.

  If it doesn't exist it will be created.
  """
  @spec ensure_schema_migrations_collection!(Ecto.Repo.t(), Keyword.t(), Keyword.t()) ::
          {Logger.level(), String.t(), Keyword.t()}
  def ensure_schema_migrations_collection!(repo, config, opts) do
    {repo, source} = get_repo_and_source(repo, config)

    create_migrations_collection(repo, source, opts ++ @default_opts)
  end

  @doc """
  Gets the repo and source collection name

  If the `:migration_repo` and/or `:migration_source` config variables are
  set then they willbe used respectively. Otherwise the default repo and
  collection name `_migrations` will be used.
  """
  @spec get_repo_and_source(Ecto.Repo.t(), Keyword.t()) :: {Ecto.Repo.t(), String.t()}
  def get_repo_and_source(repo, config) do
    {Keyword.get(config, :migration_repo, repo),
     Keyword.get(config, :migration_source, "_migrations")}
  end

  @doc """
  Gets the migrated versions from the database.
  """
  @spec versions(Ecto.Repo.t(), Keyword.t(), String.t() | atom()) ::
          {Ecto.Repo.t(), Ecto.Query.t(), Keyword.t()}
  def versions(repo, config, prefix) do
    {repo, source} = get_repo_and_source(repo, config)

    query =
      if Keyword.get(config, :migration_cast_version_field, false) do
        from(m in source, select: type(m.version, :integer))
      else
        from(m in source, select: m.version)
      end

    {repo, query, [prefix: prefix] ++ @default_opts}
  end

  @doc """
  Inserts the upped version into the migrations collection
  """
  @spec up(Ecto.Repo.t(), Keyword.t(), String.t(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def up(repo, config, version, opts) do
    {repo, source} = get_repo_and_source(repo, config)

    %__MODULE__{version: version}
    |> Ecto.put_meta(source: source)
    |> repo.insert(default_opts(opts))
  end

  @doc """
  Inserts the downed version into the migrations collection
  """
  @spec down(Ecto.Repo.t(), Keyword.t(), String.t(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def down(repo, config, version, opts) do
    {repo, source} = get_repo_and_source(repo, config)

    from(m in source, where: m.version == ^version)
    |> repo.delete_all(default_opts(opts))
  end

  defp default_opts(opts) do
    Keyword.merge(
      @default_opts,
      prefix: opts[:prefix],
      log: Keyword.get(opts, :log_migrator, false)
    )
  end

  defp create_migrations_collection(repo, source, opts) do
    collection = Collection.new(source, isSystem: true)

    commands = [
      {:add, :version, :integer, primary_key: true},
      {:add, :inserted_at, :naive_datetime, []}
    ]

    repo.__adapter__().execute_ddl(
      repo,
      {:create_if_not_exists, collection, commands},
      opts
    )
  end
end
