defmodule Test.Test do
  use ArangoXEcto.Schema
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
