defmodule ArangoXEcto.Integration.User do
  use ArangoXEcto.Schema

  import Ecto.Changeset

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
    field(:gender, Ecto.Enum, values: [male: 0, female: 1, other: 2], default: :male)
    field(:age, :integer, default: 0)
    field(:location, ArangoXEcto.Types.GeoJSON)
    field(:uuid, Ecto.UUID)
    field(:create_time, :time)
    field(:create_datetime, :utc_datetime)

    embeds_one(:class, ArangoXEcto.Integration.Class, on_replace: :delete)

    embeds_many :items, Item do
      field(:name, :string)
    end

    outgoing(:posts, ArangoXEcto.Integration.Post)

    outgoing(:posts_two, ArangoXEcto.Integration.Post,
      edge: ArangoXEcto.Integration.UserPosts,
      on_replace: :delete
    )

    outgoing(:my_posts, ArangoXEcto.Integration.Post,
      edge: ArangoXEcto.Integration.UserContent,
      on_replace: :delete
    )

    outgoing(:my_comments, ArangoXEcto.Integration.Comment,
      edge: ArangoXEcto.Integration.UserContent
    )

    outgoing(
      :my_content,
      %{
        ArangoXEcto.Integration.Post => [:title],
        ArangoXEcto.Integration.Comment => [:text]
      },
      edge: ArangoXEcto.Integration.UserContent
    )

    has_one(:best_post, ArangoXEcto.Integration.Post)

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:first_name, :last_name, :gender, :age, :location])
    |> validate_required([:last_name])
  end
end

defmodule ArangoXEcto.Integration.Class do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:name, :string)
  end
end

defmodule ArangoXEcto.Integration.DynamicClass do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  schema "dynamic_class" do
    field(:name, :string)
  end

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:name])
  end
end

defmodule ArangoXEcto.Integration.Post do
  use ArangoXEcto.Schema
  import Ecto.Changeset

  schema "posts" do
    field(:title, :string)
    field(:counter, :id)
    field(:uuid, Ecto.UUID)
    field(:links, {:map, :string})
    field(:intensities, {:map, :float})
    field(:public, :boolean, default: true)
    field(:cost, :decimal)
    field(:visits, :integer)
    field(:intensity, :float)
    field(:posted, :date)
    field(:read_only, :string)

    incoming(:users, ArangoXEcto.Integration.User)

    incoming(:users_two, ArangoXEcto.Integration.User,
      edge: ArangoXEcto.Integration.UserPosts,
      on_delete: :delete_all
    )

    outgoing(:classes, ArangoXEcto.Integration.Class, edge: ArangoXEcto.Integration.PostClasses)

    belongs_to(:user, ArangoXEcto.Integration.User)

    timestamps()
  end

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:title])
  end
end

defmodule ArangoXEcto.Integration.Comment do
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
  end
end

defmodule ArangoXEcto.Integration.Deep.Magic do
  use ArangoXEcto.Schema

  schema "magics" do
    field(:something, :string)
    field(:idk, :string)
  end
end

defmodule ArangoXEcto.Integration.UserPosts do
  use ArangoXEcto.Edge,
    from: ArangoXEcto.Integration.Post,
    to: ArangoXEcto.Integration.User

  import Ecto.Changeset

  schema "posts_users" do
    edge_fields()

    field(:type, :string)
  end

  def changeset(edge, attrs) do
    edges_changeset(edge, attrs)
    |> cast(attrs, [:type])
  end
end

defmodule ArangoXEcto.Integration.UserPostsOptions do
  use ArangoXEcto.Edge,
    from: ArangoXEcto.Integration.Post,
    to: ArangoXEcto.Integration.User

  import Ecto.Changeset

  schema "posts_users_options" do
    edge_fields()

    field(:type, :string)
  end

  def changeset(edge, attrs) do
    edges_changeset(edge, attrs)
    |> cast(attrs, [:type])
  end
end

defmodule ArangoXEcto.Integration.UserContent do
  use ArangoXEcto.Edge,
    from: ArangoXEcto.Integration.User,
    to: [ArangoXEcto.Integration.Post, ArangoXEcto.Integration.Comment]

  schema "user_content" do
    edge_fields()
  end
end

defmodule ArangoXEcto.Integration.PostClasses do
  use ArangoXEcto.Edge,
    from: ArangoXEcto.Integration.Post,
    to: ArangoXEcto.Integration.Class

  schema "post_classes" do
    edge_fields()
  end
end

defmodule ArangoXEcto.Integration.UsersView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "user_search" do
    primary_sort(:created_at, :desc)
    primary_sort(:first_name, :asc)

    store_value([:first_name, :last_name], :lz4)

    link(ArangoXEcto.Integration.User, %Link{
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

defmodule ArangoXEcto.Integration.PostsView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "post_search" do
    primary_sort(:created_at, :asc)

    store_value([:title], :lz4)

    link(ArangoXEcto.Integration.Post, %Link{
      includeAllFields: true,
      fields: %{
        title: %Link{
          analyzers: [:text_en]
        }
      }
    })

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEcto.Integration.CommentView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "comment_search" do
    link(ArangoXEcto.Integration.Comment, %Link{
      includeAllFields: true,
      fields: %{
        text: %Link{
          analyzers: [:text_en]
        }
      }
    })

    options(primarySortCompression: :lz4)
  end
end

defmodule ArangoXEcto.Integration.AnalyzerTestView do
  use ArangoXEcto.View, analyzer_module: ArangoXEcto.Integration.Analyzers

  alias ArangoXEcto.View.Link

  view "analyzer_test_view" do
    link(
      ArangoXEcto.Integration.Comment,
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

defmodule ArangoXEcto.Integration.Analyzers do
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

defmodule ArangoXEcto.Integration.NonEcto do
  defstruct [:id, :name, :__meta__]
end

defmodule ArangoXEcto.Integration.InvalidIndexes do
  use ArangoXEcto.Schema

  indexes(%{
    indexes: [fields: [:name], unique: true, name: :invalid_idx]
  })

  schema "invalid_indexes" do
    field(:name, :string)

    timestamps()
  end
end

defmodule ArangoXEcto.Integration.OneInvalidIndex do
  use ArangoXEcto.Schema

  indexes([
    [fields: [:name], unique: true, name: :valid_idx],
    [fields: [:name], name: :valid_idx],
    [fields: [:name], unique: true, name: :valid_idx2]
  ])

  schema "one_invalid_index" do
    field(:name, :string)

    timestamps()
  end
end
