defmodule Test.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Test.Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Test.Supervisor)
  end
end
