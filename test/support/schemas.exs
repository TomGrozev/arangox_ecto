defmodule ArangoXEctoTest.Integration.User do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
    field(:location, ArangoXEcto.Types.GeoJSON)

    outgoing(:posts, ArangoXEctoTest.Integration.Post)

    outgoing(:posts_two, ArangoXEctoTest.Integration.Post,
      edge: ArangoXEctoTest.Integration.UserPosts
    )

    one_outgoing(:best_post, ArangoXEctoTest.Integration.Post)

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:first_name, :last_name])
    |> validate_required([:first_name, :last_name])
  end
end

defmodule ArangoXEctoTest.Integration.Post do
  use ArangoXEcto.Schema

  schema "posts" do
    field(:title, :string)
    field(:text, :string)
    field(:views, :integer)
    field(:virt, :string, default: "iamavirtualfield", vitrual: true)

    incoming(:users, ArangoXEctoTest.Integration.User)

    incoming(:users_two, ArangoXEctoTest.Integration.User,
      edge: ArangoXEctoTest.Integration.UserPosts
    )

    one_incoming(:user, ArangoXEctoTest.Integration.User)

    timestamps()
  end
end

defmodule ArangoXEctoTest.Integration.Comment do
  use ArangoXEcto.Schema

  options(keyOptions: %{type: :uuid})

  schema "comments" do
    field(:text, :string)

    timestamps()
  end
end

defmodule ArangoXEctoTest.Integration.Deep.Magic do
  use ArangoXEcto.Schema

  schema "magics" do
    field(:something, :string)
    field(:idk, :string)
  end
end

defmodule ArangoXEctoTest.Integration.UserPosts do
  use ArangoXEcto.Edge,
    from: ArangoXEctoTest.Integration.User,
    to: ArangoXEctoTest.Integration.Post

  import Ecto.Changeset

  schema "user_posts" do
    edge_fields()

    field(:type, :string)
  end

  def changeset(edge, attrs) do
    edges_changeset(edge, attrs)
    |> cast(attrs, [:type])
  end
end
