defmodule ArangoXEctoTest.Integration.User do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
    field(:extra, :string)
    field(:extra2, :string)
    field(:gender, Ecto.Enum, values: [male: 0, female: 1, other: 2], default: :male)
    field(:location, ArangoXEcto.Types.GeoJSON)

    embeds_one(:class, ArangoXEctoTest.Integration.Class, on_replace: :delete)

    embeds_many :items, Item do
      field(:name, :string)
    end

    outgoing(:posts, ArangoXEctoTest.Integration.Post)

    outgoing(:posts_two, ArangoXEctoTest.Integration.Post,
      edge: ArangoXEctoTest.Integration.UserPosts
    )

    one_outgoing(:best_post, ArangoXEctoTest.Integration.Post)

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:first_name, :last_name, :extra, :extra2, :gender])
    |> cast_embed(:class)
    |> cast_embed(:items, with: &items_changeset/2)
    |> validate_required([:first_name, :last_name])
  end

  defp items_changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:name])
  end
end

defmodule ArangoXEctoTest.Integration.Class do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:name, :string)
  end

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:name])
  end
end

defmodule ArangoXEctoTest.Integration.Post do
  use ArangoXEcto.Schema

  schema "posts" do
    field(:title, :string)
    field(:text, :string)
    field(:views, :integer)
    field(:virt, :string, default: "iamavirtualfield", virtual: true)

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
  import Ecto.Changeset

  options(keyOptions: %{type: :uuid})

  indexes([
    [fields: [:text], unique: true, name: :comment_idx]
  ])

  schema "comments" do
    field(:text, :string)
    field(:extra, :string)

    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:text])
    |> unique_constraint(:text, name: :comment_idx)
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

defmodule ArangoXEctoTest.Integration.UserPostsOptions do
  use ArangoXEcto.Edge,
    from: ArangoXEctoTest.Integration.User,
    to: ArangoXEctoTest.Integration.Post

  import Ecto.Changeset

  options(keyOptions: %{type: :uuid})

  indexes([
    [fields: [:type], unique: true]
  ])

  schema "user_posts_options" do
    edge_fields()

    field(:type, :string)
  end

  def changeset(edge, attrs) do
    edges_changeset(edge, attrs)
    |> cast(attrs, [:type])
  end
end
