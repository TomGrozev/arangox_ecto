defmodule EctoArangodbTest.Repo do
  use Ecto.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto

  def init(_type, opts \\ %{}) do
    {:ok, opts}
  end
end
