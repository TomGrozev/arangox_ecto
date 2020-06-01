defmodule EctoArangodbTest.Repo do
  use Ecto.Repo,
    otp_app: :ecto_arangodb,
    adapter: Ecto.Adapters.ArangoDB

  def init(_type, opts \\ %{}) do
    {:ok, opts}
  end
end
