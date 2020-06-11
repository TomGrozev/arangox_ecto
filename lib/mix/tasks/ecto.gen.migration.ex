defmodule Mix.Tasks.Ecto.Gen.Migration do
  use Mix.Task

  import Mix.Ecto
  import Mix.ArangoXEcto
  import Mix.Generator
  import Macro, only: [camelize: 1, underscore: 1]

  @shortdoc "Generates a new migration for a collection"

  @moduledoc """
  Generates a migration.
  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.
  ## Examples
      mix ecto.gen.migration create_users
      mix ecto.gen.migration create_users -r Custom.Repo
  The generated migration filename will be prefixed with the current
  timestamp in UTC which is used for versioning and ordering.
  By default, the migration will be generated to the
  "priv/YOUR_REPO/migrations" directory of the current application
  but it can be configured to be any subdirectory of `priv` by
  specifying the `:priv` key under the repository configuration.
  This generator will automatically open the generated file if
  you have `ECTO_EDITOR` set in your environment variable.
  ## Command line options
    * `-r`, `--repo` - the repo to generate migration for
  """

  @aliases [
    r: :repo
  ]

  @switches [
    repo: [:string, :keep]
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    repos = parse_repo(args)

    for repo <- repos do
      case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
        {_, [name]} ->
          path = Path.join(path_to_priv_repo(repo), "migrations")
          base_name = "#{underscore(name)}.exs"
          file = Path.join(path, "#{timestamp()}_#{base_name}")

          unless File.dir?(path), do: create_directory(path)

          fuzzy_path = Path.join(path, "*_#{base_name}")

          if Path.wildcard(fuzzy_path) != [] do
            Mix.raise(
              "Migration can't be created since there is already a migration file with the name #{
                name
              }"
            )
          end

          assigns = [
            repo: repo,
            mod: Module.concat([repo, Migrations, camelize(name)])
          ]

          create_file(file, migration_template(assigns))

        {_, _} ->
          Mix.raise(
            "expected ecto.gen.migration to recieve the migration file name, " <>
              "got: #{inspect(Enum.join(args, " "))}"
          )
      end
    end
  end

  embed_template(:migration, """
  defmodule <%= inspect @mod %> do
    alias <%= @repo %>

    def up do
      :ok
    end

    def down do
      :ok
    end
  end
  """)
end
