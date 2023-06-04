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

defmodule ArangoXEctoTest.Integration.UsersView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "user_search" do
    primary_sort(:created_at, :asc)

    store_value([:first_name], :lz4)

    link(ArangoXEctoTest.Integration.User, %Link{
      includeAllFields: true,
      fields: %{
        last_name: %Link{
          analyzers: [:text_en]
        }
      }
    })

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEctoTest.Integration.CommentView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "comment_search" do
    link(
      ArangoXEctoTest.Integration.Comment,
      %Link{
        includeAllFields: true,
        fields: %{
          name: %Link{
            analyzers: [:text_en]
          }
        }
      }
    )

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEctoTest.Integration.AnalyzerTestView do
  use ArangoXEcto.View, analyzer_module: ArangoXEctoTest.Integration.Analyzers

  alias ArangoXEcto.View.Link

  view "analyzer_test_view" do
    link(
      ArangoXEctoTest.Integration.Comment,
      %Link{
        includeAllFields: true,
        fields: %{
          name: %Link{
            analyzers: [:f]
          }
        }
      }
    )

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEctoTest.Integration.FailedAnalyzerTestView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "failed_analyzer_test_view" do
    link(
      ArangoXEctoTest.Integration.Comment,
      %Link{
        includeAllFields: true,
        fields: %{
          name: %Link{
            analyzers: [:f]
          }
        }
      }
    )

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEctoTest.Integration.Analyzers do
  use ArangoXEcto.Analyzer

  identity(:a, [:norm])

  delimiter(:b, [:frequency, :position], %{
    delimiter: ","
  })

  stem(:c, [:frequency, :norm, :position], %{
    locale: "en"
  })

  norm(:d, [:frequency, :position], %{
    locale: "en",
    accent: false,
    case: :lower
  })

  ngram(:e, [], %{
    min: 3,
    max: 5,
    preserveOriginal: true,
    startMarker: "a",
    endMarker: "b",
    streamType: :binary
  })

  text(:f, [:frequency, :norm], %{
    locale: "en",
    accent: false,
    case: :lower,
    stemming: false,
    edgeNgram: %{
      min: 3
    },
    stopwords: ["abc"]
  })

  collation(:g, [:frequency], %{
    locale: "en"
  })

  aql(:h, [:norm], %{
    queryString: "RETURN SOUNDEX(@param)",
    collapsePositions: true,
    keepNull: false,
    batchSize: 500,
    memoryLimit: 2_097_152,
    returnType: :string
  })

  pipeline :i, [:frequency] do
    norm(:x, [], %{
      locale: "en",
      accent: false,
      case: :lower
    })

    text(:y, [], %{
      locale: "en",
      accent: false,
      stemming: true,
      case: :lower
    })
  end

  stopwords(:j, [], %{
    stopwords: ["xyz"],
    hex: false
  })

  segmentation(:k, [], %{
    break: :all,
    case: :none
  })

  geojson(:l, [:norm], %{
    type: :shape,
    options: %{
      maxCells: 21,
      minLevel: 5,
      maxLevel: 24
    }
  })

  geopoint(:m, [:norm], %{
    latitude: ["lat", "latitude"],
    longitude: ["long", "longitude"],
    options: %{
      maxCells: 21,
      minLevel: 5,
      maxLevel: 24
    }
  })

  build()
end
