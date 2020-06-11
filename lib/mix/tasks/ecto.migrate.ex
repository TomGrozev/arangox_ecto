defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task

  import Mix.ArangoXEcto

  @shortdoc "Runs Migration/Rollback functions from migration modules"

  @aliases [
    d: :dir
  ]

  @switches [
    dir: :string
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case migrated_versions() do
      [nil] ->
        Mix.raise("ArangoXEcto is not set up, run `mix ecto.setup.arango` first.")

      _ ->
        migrate(args)
    end
  end

  defp migrate(args) do
    case OptionParser.parse!(args, aliases: @aliases, strict: @switches) do
      {[], []} ->
        up()

      {[dir: "up"], _} ->
        up()

      {_, ["up"]} ->
        up()

      {[dir: "down"], _} ->
        down()

      {_, ["down"]} ->
        down()

      {_, ["rollback"]} ->
        down()

      {_, _} ->
        Mix.raise("Unknown arguments provided, #{inspect(Enum.join(args, " "))}")
    end
  end

  defp up do
    pending_migrations()
    |> Enum.each(fn file_path ->
      case apply(migration_module(file_path), :up, []) do
        :ok ->
          file_path
          |> timestamp()
          |> update_versions()

          Mix.shell().info("Successfully Migrated #{file_path}")

        {:error, reason} ->
          Mix.shell().info("Unable to Migrate #{file_path}")
          Mix.shell().error("Status: " <> inspect(reason))
      end
    end)
  end

  def down do
    [last_migrated_version | _] = versions()

    module =
      last_migrated_version
      |> migration_path()
      |> migration_module()

    case apply(module, :down, []) do
      :ok ->
        remove_version(last_migrated_version)

        Mix.shell().info("Successfully Rolled Back #{last_migrated_version}")

      _ ->
        Mix.shell().info("Unable to Rollback #{last_migrated_version}")
    end
  end

  defp migration_module(path) do
    {{:module, module, _, _}, _} =
      get_default_repo!()
      |> path_to_priv_repo()
      |> Path.join("migrations")
      |> Path.join(path)
      |> Code.eval_file()

    module
  end

  defp migration_path(version) when not is_binary(version) do
    version
    |> to_string()
    |> migration_path()
  end

  defp migration_path(version) do
    get_default_repo!()
    |> path_to_priv_repo()
    |> Path.join("migrations")
    |> File.ls!()
    |> Enum.find(&String.starts_with?(&1, version))
  end

  defp pending_migrations do
    get_default_repo!()
    |> path_to_priv_repo()
    |> Path.join("migrations")
    |> File.ls!()
    |> Enum.filter(&(!String.starts_with?(&1, ".")))
    #    |> Enum.filter(&(timestamp(&1) not in versions()))
    |> Enum.sort(&(timestamp(&1) <= timestamp(&2)))
  end

  defp timestamp(path) do
    path
    |> String.split("_")
    |> hd()
    |> String.to_integer()
  end

  defp versions do
    migrated_versions()
    |> Enum.sort(&(&1 >= &2))
  end
end
