defmodule Mix.Tasks.Ecto.Setup.Arango do
  use Mix.Task
  import Mix.ArangoXEcto

  @shortdoc "Sets up all necessary collections in _systems db for migrations"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case create_migrations() do
      :ok ->
        create_master_document()
        Mix.shell().info("Setup Complete")

      {:error, 409} ->
        Mix.shell().info("ArangoDB already setup for ecto")
    end
  end
end
