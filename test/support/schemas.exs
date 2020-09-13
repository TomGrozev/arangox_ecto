defmodule ArangoXEctoTest.Integration.User do
  use ArangoXEcto.Schema

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
  end
end

defmodule ArangoXEctoTest.Integration.Post do
  use ArangoXEcto.Schema

  schema "posts" do
    field(:title, :string)
    field(:text, :string)
  end
end

defmodule ArangoXEctoTest.Integration.UserPosts do
  use ArangoXEcto.Schema.Edge
  import Ecto.Changeset

  schema "user_posts" do
    edge_fields()

    field(:type, :string)
  end

  def changeset(edge, attrs) do
    edges_changeset(edge, attrs)
    |> cast(attrs, [:type])
    |> validate_required([:type])
  end
end
