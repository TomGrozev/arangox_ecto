defmodule Test.Repo do
  use Ecto.Repo,
    otp_app: :ecto_arangodb,
    adapter: Ecto.Adapters.ArangoDB
end
