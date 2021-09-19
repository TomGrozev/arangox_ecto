defmodule Mix.ArangoXEcto do
  @moduledoc """
  Migration task helper functions
  """

  @doc """
  Creates the database specified in the config
  """
  @spec create_base_database() :: {:ok, String.t()} | {:error, Integer.t()}
  def create_base_database do
    config()
    |> Keyword.get(:database)
    |> create_database()
  end

  @doc """
  Creates a new database of `name`
  """
  @spec create_database(String.t()) :: {:ok, String.t()} | {:error, Integer.t()}
  def create_database(name) when is_binary(name) do
    {:ok, conn} = system_db()

    Arangox.post(conn, "/_api/database", %{name: name})
    |> format_response(name)
  end

  @doc """
  Creates the migrations collection

  Creates an empty system collection to store migrations.
  """
  @spec create_migrations :: :ok | {:error, Integer.t()}
  def create_migrations do
    {:ok, conn} = system_db()

    Arangox.post(conn, "/_api/collection", %{
      type: 2,
      isSystem: true,
      name: "_migrations"
    })
    |> format_response()
  end

  @doc """
  Creates a document to store migrations

  Creates a document with key of the database name. Seperating the migrations
  into seperate documents allow for more organisation and better debugging.
  """
  @spec create_migration_document() :: :ok | {:error, Integer.t()}
  def create_migration_document do
    {:ok, conn} = system_db()

    key =
      config()
      |> Keyword.fetch!(:database)

    Arangox.post(conn, "/_api/document/_migrations", %{_key: key, migrations: []})
    |> format_response()
  end

  @doc """
  Gets the path to the priv repo folder

  Will return a full file path to the priv/repo folder.
  """
  def path_to_priv_repo(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    Path.join(Mix.Project.deps_paths()[app] || File.cwd!(), "priv/repo")
  end

  @doc """
  Creates a timestamp for the migration file
  """
  def timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  @doc false
  def migrated_versions do
    {:ok, conn} = system_db()

    {:ok, versions} =
      query(conn, """
        RETURN DOCUMENT("_migrations/MASTER").migrations
      """)

    versions
  end

  @doc false
  def update_versions(version) when is_binary(version),
    do: update_versions(String.to_integer(version))

  def update_versions(version) do
    {:ok, conn} = system_db()

    migrated = migrated_versions()

    if Enum.member?(migrated, version) do
      migrated
    else
      new_versions = [version | migrated]

      {:ok, _} =
        Arangox.patch(conn, "/_api/document/_migrations/MASTER", %{migrations: new_versions})

      new_versions
    end
  end

  @doc false
  def remove_version(version) when is_binary(version),
    do: remove_version(String.to_integer(version))

  def remove_version(version) do
    {:ok, conn} = system_db()

    new_versions =
      migrated_versions()
      |> List.delete(version)

    {:ok, _} =
      Arangox.patch(conn, "/_api/document/_migrations/MASTER", %{migrations: new_versions})

    new_versions
  end

  @doc """
  Gets the default repo

  The first in the list of running repos is used.
  """
  def get_default_repo! do
    Mix.Ecto.parse_repo([])
    |> List.first()
    |> case do
      nil -> Mix.raise("No Default Repo Found")
      repo -> repo
    end
  end

  defp query(conn, query_str) do
    Arangox.transaction(conn, fn cursor ->
      cursor
      |> Arangox.cursor(query_str)
      |> Enum.reduce([], fn resp, acc ->
        acc ++ resp.body["result"]
      end)
      |> List.flatten()
    end)
  end

  defp config(opts \\ []) do
    get_default_repo!().config()
    |> Keyword.merge(opts)
    |> ensure_endpoint_value()
  end

  defp ensure_endpoint_value(config) do
    if Keyword.has_key?(config, :endpoints) do
      config
    else
      Keyword.put(config, :endpoints, "http://localhost:8529")
    end
  end

  defp system_db do
    options =
      config(
        pool_size: 1,
        database: "_system"
      )

    Arangox.start_link(options)
  end

  defp format_response(response, pass_arg \\ nil)

  defp format_response({:ok, _}, nil), do: :ok

  defp format_response({:ok, _}, pass_arg) when not is_nil(pass_arg), do: {:ok, pass_arg}

  defp format_response({:error, %{status: status}}, _), do: {:error, status}

  defp format_response({:error, _reason}, _), do: {:error, 0}

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end
