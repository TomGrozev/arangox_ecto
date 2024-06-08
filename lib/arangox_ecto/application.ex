defmodule ArangoXEcto.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: ArangoXEcto.MigratorSupervisor},
      {Task.Supervisor, name: ArangoXEcto.StorageSupervisor}
    ]

    opts = [strategy: :one_for_one, name: ArangoXEcto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
