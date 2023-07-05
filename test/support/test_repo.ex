defmodule ArangoXEctoTest.Repo do
  use Ecto.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto.Adapter
end

defmodule ArangoXEctoTest.StaticRepo do
  use Ecto.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto.Adapter
end

defmodule ArangoXEctoTest.ArangoRepo do
  use Ecto.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto.Adapter
end
