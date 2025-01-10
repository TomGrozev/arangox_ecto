defmodule Mix.Tasks.Arango.Gen.Migration do
  @moduledoc """
  Generates a ArangoXEcto migration.

  Unlike the default `ecto_sql` implementation, this will only generated migrations for repos that
  use the ArangoXEcto.Adapter. This prevents it trying to run ArangoDB migrations on 
  non-ArangoXEcto repos. This is particularly useful for when using multiple database providers in
  one app, e.g. ArangoXEcto and PostgreSQL (through `ecto_sql`).

  The repository must be set under `:ecto_repos` in the current app
  configuration or given via the `-r` option.

  ## Examples

      mix arango.gen.migration create_users
      mix arango.gen.migration create_users -r Custom.Repo

  The generated migration filename will be prefixed with the current timestamp
  in UTC which is used for versioning and ordering.

  By default, the migration will be generated to the
  `priv/YOUR_REPO/migrations` directory of the current application but it can
  be configured to be any subdirectory of `priv` by specifying the `:priv` key
  under the repository configuration.

  This generator will automatically open the generated file if you have
  `ECTO_EDITOR` set in your environment variable.

  ## Command line options

    * `-r`, `--repo` - the repo to generate migration for
    * `--no-compile` - does not compile applications before running
    * `--no-deps-check` - does not check dependencies before running
    * `--migrations-path` - the path to run the migrations from, defaults to `priv/repo/migrations`

  ## Configuration

  If the current app configuration specifies a custom migration module
  the generated migration code will use that rather than the default
  `ArangoXEcto.Migration`:

      config :arangox_ecto, migration_module: MyApplication.CustomMigrationModule

  """

  use Mix.Task

  import Mix.Ecto
  import Mix.ArangoXEcto
  import Mix.Generator
  import Macro, only: [camelize: 1, underscore: 1]

  @aliases [
    r: :repo
  ]

  @switches [
    change: :string,
    repo: [:string, :keep],
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :string
  ]

  @impl true
  def run(args) do
    repos = parse_repo(args)

    repos
    |> Stream.map(&ensure_repo(&1, args))
    |> Stream.filter(&(&1.__adapter__() == ArangoXEcto.Adapter))
    |> Enum.each(fn repo ->
      case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
        {opts, [name]} ->
          generate_migration(repo, opts, name)

        {_, _} ->
          Mix.raise(
            "expected arango.gen.migration to receive the migration file name, " <>
              "got: #{inspect(Enum.join(args, " "))}"
          )
      end
    end)
  end

  defp generate_migration(repo, opts, name) do
    path = opts[:migrations_path] || Path.join(source_repo_priv(repo), "migrations")
    base_name = "#{underscore(name)}.exs"
    file = Path.join(path, "#{timestamp()}_#{base_name}")
    if !File.dir?(path), do: create_directory(path)

    fuzzy_path = Path.join(path, "*_#{base_name}")

    if Path.wildcard(fuzzy_path) != [] do
      Mix.raise(
        "Migration can't be created since there is already a migration file with the name #{name}"
      )
    end

    assigns = [
      mod: Module.concat([repo, Migrations, camelize(name)]),
      change: opts[:change]
    ]

    create_file(file, migration_template(assigns))

    if open?(file) and Mix.shell().yes?("Do you want to run this migration?") do
      Mix.Task.run("arango.migrate", ["-r", inspect(repo), "--migrations-path", path])
    end

    file
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp migration_module do
    case Application.get_env(:arangox_ecto, :migration_module, ArangoXEcto.Migration) do
      migration_module when is_atom(migration_module) -> migration_module
      other -> Mix.raise("Expected :migration_module to be a module, got: #{inspect(other)}")
    end
  end

  embed_template(:migration, """
  defmodule <%= inspect @mod %> do
    use <%= inspect migration_module() %>

    def change do
  <%= @change %>
    end
  end
  """)
end
