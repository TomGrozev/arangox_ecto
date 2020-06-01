defmodule EctoArangodbTest.Test do
  use Ecto.Adapters.ArangoDB.Schema
  import Ecto.Changeset

  schema "test" do
    field(:title, :string)

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end
