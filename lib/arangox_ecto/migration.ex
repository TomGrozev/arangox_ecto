defmodule ArangoXEcto.Migration do
  @moduledoc """
  Modify the database through static migrations.

  > #### NOTE {: .info}
  >
  > ArangoXEcto can dynamically create collections for you and can be enabled by setting `static:
  > false` in your app config. Refer to `ArangoXEcto` for more info. However, this is primarily
  useful for dev applications and migrations should be used for production level applications.

  Each migrations typically have an `up` and `down` function or just a `change` function. If using
  separate `up` and `down` functions, these will allow for the database to migrated forward or
  rolled back. If using the `change` function then the migrations for going forward are defined and
  automatically reversed in the case of a rollback.

  Migrations that have been executed in a database for ArangoXEcto are stored in a system collection
  called `_migrations` (this is a hidden system collection). This allows ArangoXEcto to track what
  has already been run so that it knows what migrations can be run or rolled back. You can configure
  the name of this table with the `:migration_source` configuration option and the name of the
  repository that manages migrations can be configured with `:migration_repo`.

  ## Two (or more) servers, one DB, oh no!!

  You might be wondering what happens when there are two or more applications trying to run
  migrations on the database at once. If two or more instances of the database try to write to the
  database at the same time this could be a huge problem, causing unpredictable results. A lot of
  databases use locking as a mechanism to solve this. I.e. one connection will lock writing to the
  database so others cannot write. ArangoDB doesn't do this, so how can we solve this? 

  Luckily we don't have to worry about this as ArangoDB handles this for us through dynamic locks.
  Essentially if two connections try to write on the same part of the database then one of them will
  just fail as the first has acquired an exclusive lock.

  ## Migration creation

  Migration files are stored in the "priv/MY_REPO/migrations" (where MY_REPO is a lowercase
  underscored name of your repository. For example, if you repo module was `MyApp.MyRepo` then the
  path would be "priv/my_repo/migrations" or if your repo module was `MyApp.ThisIsTheCoolestRepo`
  then your migrations would be in "priv/this_is_the_coolest_repo/migrations". The directory can
  be overridden when running the mix tasks or in the configuration.

  Each migration filename will have a timestamp number followed by a unique name seperated by an
  underscore. For example if you wanted to add a users collection could put the migration in a file
  at "priv/repo/migrations/20240928200000_add_users_collection.exs, with contents:

      defmodule Repo.Migrations.AddUsersCollection do
        use ArangoXEcto.Migration

        def up do
          create collection(:users) do
            add :first_name, :string, comment: "first_name column"
            add :last_name, :string
            add :gender, :integer
            add :age, :integer
            add :location, :map

            timestamps()
          end
        end

        def down do
          drop collection("users")
        end
      end

  The `up/0` function is responsible for migrating the database forward, while the `down/0` function
  is responsible for rolling back this migration. The `down/0` function must always reverse the
  `up/0` action. Inside both of these functions we use various API methods defined in this module to
  perform actions on the database. We can manage collections, indexes, views, analyzers and run
  custom AQL commands.

  Now that our migration is setup, all that is left is to execute it. While migrations can be run
  using code (and there are valid use cases for this, e.g. generating releases for production) we
  generally will use mix tasks. To do this run the following from the root directory of your
  project:

      $ mix arango.migrate

  If we wanted to reverse the migration we could run:

      $ mix arango.rollback -n 1

  We must always specify how many migrations to rollback. Whereas `mix arango.migrate` will always
  run all pending migrations

  There is one other mix task that is used regularly and it saves us a lot of time. That is the `mix
  arango.gen.migration` task. This task will generate a blank migration with boilerplate contents
  and use the proper timestamps of when it was generated.

      $ mix arango.gen.migration add_users_collection

  You can now generate and run migrations successfully. You may be pretty proud of yourself, and
  you should be, but there is some more parts to it. You can learn all about migrations in
  ArangoXEcto in this module documentation.

  > #### IMPORTANT {: .warning}
  > **Order matters!!** Make sure you create collections before indexes and views, and analyzers 
  > before views if they are used. In general this is a good order to follow:
  >
  >    Analyzers > Collections > Indexes > Views

  ## ArangoDB Schemas

  ArangoDB can take a schema, but it is not strictly required, hence no fields _need_ to be 
  provided. The only required thing is the collection name. More info below on how to define
  fields. For example, the example provided in the previous section can be provided without defining
  the fields.

      defmodule Repo.Migrations.AddUsersCollection do
        use ArangoXEcto.Migration

        def up do
          create collection(:users)
        end

        def down do
          drop collection("users")
        end
      end

  This will work perfectly fine, however there is one caveat, documents in the collection will not
  be validated. This means that the migration will only create the collection and not define a
  JSONSchema for the collection. Schemas a generated using the `ArangoXEcto.Migration.JsonSchema`
  module, however all documentation on how to use it can be found in this module.

  ## Mix tasks

  As seen in the example above, ArangoXEcto has a few built in mix tasks that can be used to help
  with the development workflow. These tasks are similar to the ones found in `ecto_sql` but are
  adapted for the `ArangoXEcto` context. To allow for using multiple database adapters together they
  follow a similar but slightly different pattern, as seen below.

    * `mix arango.gen.migration` - generates a migration that the user can fill in with particular
      commands
    * `mix arango.migrate` - migrates a repository
    * `mix arango.rollback` - rolls back a particular migration

  For additional help on how to use these tasks you can run `mix help COMMAND` where `COMMAND` is
  the command you need assistance with.

  As mentioned previously, you can also run migrations using code using this module. If you think
  you're pretty cool and know what you're doing you can also use the lower level APIs in
  `ArangoXEcto.Migrator`.

  ## Change (combining up and down)

  I know what you're thinking, "Ugh, do I really have to write an `up/0` and `down/0` function for
  every single migration? Surely you could have just written some code the generate the `down/0`
  version for me". Well yes, yes I did. That's what `change/0` is for. You just write your regular
  `up/0` action and it will do some fancy footwork and figure out what the `down/0` version would
  be. For example, this would operate the same as seen above:

      defmodule Repo.Migrations.AddUsersCollection do
        use ArangoXEcto.Migration

        def change do
          create collection(:users) do
            add :first_name, :string, comment: "first_name column"
            add :last_name, :string
            add :gender, :integer
            add :age, :integer
            add :location, :map

            timestamps()
          end
        end
      end

  Like a good salesman I only gave you half the story, there is one caveat when using this. Not all
  commands are reversible and will raise an `Ecto.MigrationError`.

  A great example of a command that cannot be reversed is `execute/1` but can easily be made
  reversible by calling `execute/2` instead. The first argument will be run on `up/0` and the second
  will be run on `down/0`.

  If you implement `up/0` and `down/0` they will take precedence over `change/0` which won't be
  invoked.

  ## Field Types

  The field types provided must match one of the types available in
  `ArangoXEcto.Migration.JsonSchema`. Any other option will raise an error. There is one caveat to
  this, the `sub_command` option is used through `add_embed` and `add_embed_many` (essentially a
  shortcut for an array of many embeds).

  The options that can be passed to each of the types can be found in the
  `ArangoXEcto.Migration.JsonSchema` docs.

  ## Executing and flushing

  Most functions won't be executed until the end of the relevant `up`, `change` or `down` callback.
  However, if you call any `Ecto.Repo` function they will be executed immediately, unless called
  inside an anonymous function passed to `execute/1`.

  You may want to ensure that all the previous steps have been executed before continuing. To do
  this you can call the `flush/0` function to execute everything before.

  However `flush/0` will raise if it would be called from `change` function when doing a rollback.
  To avoid that we recommend to use `execute/2` with anonymous functions instead.
  For more information and example usage please take a look at `execute/2` function.

  ## Repo configuration

  ### Migrator configuration

  The following options are not required but can be used to adjust how your migrations are stored
  and run.

    * `:migration_source` - The name of the collection to store the migrations that have already
      been run. Only the version numbers (timestamps) are stored. The default is `_migrations`.
      Whatever is specified it will be set as a system collection in ArangoDB. The convention is to
      prefix the collection name with an underscore (_). You can configure this as follows:

          config :my_app, MyApp.Repo, migration_source: "_custom_migrations"

    * `:migration_repo` - This configures which repository the migrations will be stored in. By
      default this will be the given repository but it can be overridden. A possible use case of
      this is if you wanted all migrations to be stored in a particular database in ArangoDB.

          config :my_app, MyApp.Repo, migration_repo: MyApp.MigrationRepo

    * `:priv` - the location where to store important assets, such as migrations. By default this
      will be "priv/my_reoo" for a repository module of `MyApp.MyRepo` and migrations would be
      placed in "priv/my_repo/migrations".

    * `:start_apps_before_migration` - A list of applications to be started before migrations are
      run. Used by `ArangoXEcto.Migrator.with_repo/3` and hence the migration task.

          config :my_app, MyApp.Repo, start_apps_before_migration: [:ssl, :some_custom_logger]

  ### Migrations configuration

  The previous section's options were focused on how migrations are run and stored, whereas the
  following options are focused on adjusting what values are stored. If you change these after your
  app goes into production it will cause unexpected behaviour.

    * `:migration_timestamps` - Modifies the type and field names of `:inserted_at` and
      `:updated_at`. By default timestamps will be stored as `:naive_datetime` but this, and the
      field names can be configured as seen below:

          config :my_app, MyApp.Repo, migration_timestamps: [
            type: :utc_datetime,
            inserted_at: :created_at,
            updated_at: :changed_at
          ]

    * `:migration_default_prefix` - By default no prefix is used, but you might want to. You can
      configure it using this option. This will be overriden by a prefix being passed at the command
      level.

          config :my_app, MyApp.Repo, migration_default_prefix: "my_migrations_prefix"

  ## Comments

  The schema stored in ArangoDB supports storing comments on the fields. You can specify this by
  passing the `:comment` option when using the `add/3`, `add_embed/3`, `add_embed_many/3` and the
  modify equivalents.

        def up do
          create collection(:users) do
            add :name, :string, comment: "full name column"
            add_embed :facts, comment: "my facts" do
              add :statement, :string, comment: "represents the fact statement"
              add :falsehood, :boolean, comment: "is the fact false?"
            end

            timestamps()
          end
        end

  ## Prefixes

  ArangoXEcto fully supports prefixes, which includes in migrations. Unlike in a database provider
  like PostgreSQL, ArangoDB doesn't have the notion of prefixes, hence prefixes actually create a
  separate database to create the separation.

        def up do
          create collection(:users, prefix: "base_app") do
            add :first_name, :string, comment: "first_name column"
            add :last_name, :string
            add :gender, :integer
            add :age, :integer
            add :location, :map

            timestamps()
          end

          create index(:users, [:age], prefix: "base_app")
        end

  Notice here how the same prefix must be specified on both the collection creation and the index
  creation. If you don't do this then they simply won't be created in the same database and will
  likely result in an error. You can specify a default prefix, as mentioned above, using the
  `:migration_default_prefix` in your configuration.

  ## Transaction Callbacks

  Migrations are run in transactions. You may need to perform some actions after beginning a
  transaction or before committing the migration. You can do this with the `c:after_begin/0` and
  `c:before_commit/0` callbacks to your migration.

  Sometimes you may want to use these callbacks for every migration and doing so can be quite
  repetitive. You can solve this by implementing your own migration module that extends the
  `ArangoXEcto.Migration` module:

      defmodule MyApp.Migration do
        defmacro __using__(_) do
          quote do
            use ArangoXEcto.Migration

            def after_begin() do
              repo().query! "SOME ARANGO QUERY"
            end
          end
        end
      end

  Then in your migrations you can replace `use ArangoXEcto.Migration` with `use MyApp.Migration`.

  ## Example

      defmodule MyProject.Repo.Migrations.CreateUsers do
        use ArangoXEcto.Migration

        def change do
          create analyzer(:norm_en, :norm, [:frequency, :position], %{
             locale: "en",
             accent: false,
             case: :lower
           })

          create collection(:users) do
            add :first_name, :string, comment: "first_name column"
            add :last_name, :string
            add :gender, :integer
            add :age, :integer
            add :location, :map

            timestamps()
          end

          create index(:users, [:age])
          create unique_index(:users, [:location])

          create view(:user_search, commitIntervalMsec: 1, consolidationIntervalMsec: 1) do
            add_sort(:created_at, :desc)
            add_sort(:first_name)

            add_store([:first_name, :last_name], :none)

            add_link("users", %Link{
              includeAllFields: true,
              fields: %{
                last_name: %Link{
                  analyzers: [:identity, :norm_en]
                }
              }
            })
          end
        end
      end
  """

  require Logger

  alias ArangoXEcto.Analyzer
  alias ArangoXEcto.Migration.Runner
  alias ArangoXEcto.View.Link

  defmodule View do
    @moduledoc """
    Used internally by the `ArangoXEcto` migration.

    To define a view in a migration, see `ArangoXEcto.Migration.view/2`.
    """

    @enforce_keys [:name]
    defstruct [
      :name,
      :consolidationIntervalMsec,
      :consolidationPolicy,
      :commitIntervalMsec,
      :writebufferSizeMax,
      :writebufferIdle,
      :writebufferActive,
      :cleanupIntervalStep,
      :primarySortCompression,
      :prefix,
      type: "arangosearch",
      links: %{},
      primarySort: [],
      storedValues: []
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            consolidationIntervalMsec: integer() | nil,
            consolidationPolicy: String.t() | nil,
            commitIntervalMsec: integer() | nil,
            writebufferSizeMax: integer() | nil,
            writebufferIdle: boolean() | nil,
            writebufferActive: boolean() | nil,
            cleanupIntervalStep: integer() | nil,
            primarySortCompression: boolean(),
            prefix: String.t() | nil,
            type: String.t(),
            links: map(),
            primarySort: list(),
            storedValues: list()
          }

    @type view_option ::
            :consolidationIntervalMsec
            | :consolidationPolicy
            | :commitIntervalMsec
            | :writebufferSizeMax
            | :writebufferIdle
            | :writebufferActive
            | :cleanupIntervalStep
            | :primarySortCompression
            | :prefix

    @doc """
    Creates a new View struct
    """
    @spec new(atom() | String.t(), [view_option()]) :: t()
    def new(name, opts \\ [])
    def new(name, opts) when is_atom(name), do: new(Atom.to_string(name), opts)

    def new(name, opts) do
      keys = Keyword.merge(opts, name: name, type: "arangosearch")

      struct(__MODULE__, keys)
    end
  end

  defmodule Analyzer do
    @moduledoc """
    Used internally by the `ArangoXEcto` migration.

    To define an analyzer in a migration, see `ArangoXEcto.Migration.analyzer/4`.
    """

    @enforce_keys [:name]
    defstruct [
      :name,
      :type,
      :features,
      :prefix,
      properties: %{}
    ]

    @type type ::
            :identity
            | :delimiter
            | :stem
            | :norm
            | :ngram
            | :text
            | :collation
            | :aql
            | :pipeline
            | :stopwords
            | :segmentation
            | :minhash
            | :classification
            | :nearest_neighbors
            | :geojson
            | :geo_s2
            | :geopoint

    @type feature :: :frequency | :norm | :position

    @type t :: %__MODULE__{
            name: String.t(),
            type: type(),
            features: feature(),
            prefix: String.t() | nil,
            properties: map()
          }

    @doc """
    Creates a new Analyzer struct
    """
    @spec new(atom() | String.t(), type(), [feature()], map(), prefix: atom()) :: t()
    def new(name, type, features, properties \\ %{}, opts \\ [])

    def new(name, type, features, properties, opts) when is_atom(name),
      do: new(Atom.to_string(name), type, features, properties, opts)

    def new(name, type, features, properties, opts) when is_binary(name) do
      validate_type!(type)
      validate_features!(features)
      validate_properties!(properties, name, type)

      keys =
        Keyword.merge(opts, name: name, type: type, features: features, properties: properties)

      struct(__MODULE__, keys)
    end

    @valid_types [
      :identity,
      :delimiter,
      :stem,
      :norm,
      :ngram,
      :text,
      :collation,
      :aql,
      :pipeline,
      :stopwords,
      :segmentation,
      :minhash,
      :classification,
      :nearest_neighbors,
      :geojson,
      :geo_s2,
      :geopoint
    ]

    @doc false
    @spec validate_type!(atom()) :: :ok
    def validate_type!(type) do
      if type not in @valid_types do
        raise ArgumentError,
              "the type for analyzer must be one of (#{inspect(@valid_types)}), got: #{inspect(type)}"
      end

      :ok
    end

    @valid_keys [:frequency, :norm, :position]

    @doc false
    @spec validate_features!([atom()]) :: :ok
    def validate_features!(features) do
      if !(is_list(features) and Enum.all?(features, &Enum.member?(@valid_keys, &1))) do
        raise ArgumentError,
              "the features provided are invalid, only accepts keys [:frequency, :norm, :position], got: #{inspect(features)}"
      end

      :ok
    end

    @doc false
    @spec validate_properties!([atom()], atom(), type()) :: :ok
    def validate_properties!(properties, name, type) do
      keys = valid_keys(type)

      !Enum.all?(properties, fn {k, v} ->
        Enum.member?(keys, k) and valid_key?(k, v)
      end)
      |> if do
        raise ArgumentError,
              "the properties provided for analyzer '#{name}' are invalid, only accepts keys #{inspect(keys)}, got: #{inspect(properties)}"
      end

      :ok
    end

    defp valid_keys(:delimiter), do: [:delimiter]
    defp valid_keys(:stem), do: [:locale]
    defp valid_keys(:norm), do: [:locale, :accent, :case]
    defp valid_keys(:collation), do: [:locale]
    defp valid_keys(:stopwords), do: [:stopwords, :hex]
    defp valid_keys(:segmentation), do: [:break, :graphic, :case]
    defp valid_keys(:minhash), do: [:numHashes, :analyzer]
    defp valid_keys(:classification), do: [:model_location, :top_k, :threshold]
    defp valid_keys(:nearest_neighbors), do: [:model_location, :top_k]
    defp valid_keys(:geojson), do: [:type, :options]
    defp valid_keys(:geo_s2), do: [:format, :type, :options]
    defp valid_keys(:geopoint), do: [:latitude, :longitude, :options]
    defp valid_keys(:pipeline), do: [:pipeline]

    defp valid_keys(:ngram) do
      [
        :min,
        :max,
        :preserveOriginal,
        :startMarker,
        :endMarker,
        :streamType
      ]
    end

    defp valid_keys(:text) do
      [
        :locale,
        :accent,
        :case,
        :stemming,
        :edgeNgram,
        :stopwords,
        :stopwordsPath
      ]
    end

    defp valid_keys(:aql) do
      [
        :queryString,
        :collapsePositions,
        :keepNull,
        :batchSize,
        :memoryLimit,
        :returnType
      ]
    end

    defp valid_keys(_), do: []

    defp valid_key?(:delimiter, value), do: is_binary(value)
    defp valid_key?(:locale, value), do: is_binary(value)
    defp valid_key?(:accent, value), do: is_boolean(value)
    defp valid_key?(:case, value), do: value in [:none, :lower, :upper]
    defp valid_key?(:min, value), do: is_integer(value)
    defp valid_key?(:max, value), do: is_integer(value)
    defp valid_key?(:preserveOriginal, value), do: is_boolean(value)
    defp valid_key?(:startMarker, value), do: is_binary(value)
    defp valid_key?(:endMarker, value), do: is_binary(value)
    defp valid_key?(:streamType, value), do: value in [:binary, :utf8]
    defp valid_key?(:stemming, value), do: is_boolean(value)
    defp valid_key?(:stopwords, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
    defp valid_key?(:stopwordsPath, value), do: is_binary(value)
    defp valid_key?(:queryString, value), do: is_binary(value)
    defp valid_key?(:collapsePositions, value), do: is_boolean(value)
    defp valid_key?(:keepNull, value), do: is_boolean(value)
    defp valid_key?(:batchSize, value), do: is_integer(value) and value >= 1 and value <= 1000
    defp valid_key?(:numHashes, value), do: is_integer(value) and value >= 1
    defp valid_key?(:hex, value), do: is_boolean(value)
    defp valid_key?(:model_location, value), do: is_binary(value)
    defp valid_key?(:top_k, value), do: is_integer(value)
    defp valid_key?(:threshold, value), do: is_float(value) or is_integer(value)
    defp valid_key?(:latitude, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
    defp valid_key?(:longitude, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
    defp valid_key?(:returnType, value), do: value in [:string, :number, :bool]
    defp valid_key?(:break, value), do: value in [:all, :alpha, :graphic]
    defp valid_key?(:type, value), do: value in [:shape, :centroid, :point]
    defp valid_key?(:format, value), do: value in [:latLngDouble, :latLngInt, :s2Point]
    defp valid_key?(:analyzer, %Analyzer{}), do: true

    defp valid_key?(:pipeline, analyzers),
      do: Enum.all?(analyzers, fn analyzer -> match?(%Analyzer{}, analyzer) end)

    defp valid_key?(:memoryLimit, value),
      do: is_integer(value) and value >= 1_048_576 and value <= 33_554_432

    defp valid_key?(:edgeNgram, value) do
      is_map(value) and
        Enum.all?(value, fn {k, v} ->
          k in [:min, :max, :preserveOriginal] and valid_key?(k, v)
        end)
    end

    defp valid_key?(:options, value) do
      is_map(value) and
        Enum.all?(value, fn {k, v} ->
          k in [:maxCells, :minLevel, :maxLevel] and is_integer(v)
        end)
    end

    defp valid_key?(_, _), do: false

    @doc false
    def definition(analyzer) do
      case Map.get(analyzer.properties, :pipeline) do
        nil ->
          analyzer

        pipeline ->
          Map.update!(analyzer, :properties, fn props ->
            Map.put(props, :pipeline, Enum.map(pipeline, &Map.from_struct/1))
          end)
      end
      |> Map.from_struct()
    end
  end

  defmodule Index do
    @moduledoc """
    Used internally by the `ArangoXEcto` migration.

    To define an index in a migration, see `ArangoXEcto.Migration.index/3`.

    The attributes in this struct are directly passed to the
    ArangoDB API for creation. No validation is done on the
    attributes and is left to the database to manage.
    """

    @enforce_keys [:collection_name]
    defstruct [
      :collection_name,
      :fields,
      :sparse,
      :unique,
      :deduplication,
      :minLength,
      :geoJson,
      :expireAfter,
      :prefix,
      :name,
      type: :hash
    ]

    @type t :: %__MODULE__{
            collection_name: String.t(),
            fields: [atom()],
            sparse: boolean() | nil,
            unique: boolean() | nil,
            deduplication: boolean() | nil,
            minLength: integer() | nil,
            geoJson: boolean() | nil,
            expireAfter: integer() | nil,
            prefix: String.t() | nil,
            name: String.t(),
            type: :hash
          }

    @type index_option ::
            {:type, atom}
            | {:prefix, String.t()}
            | {:unique, boolean}
            | {:sparse, boolean}
            | {:deduplication, boolean}
            | {:minLength, integer}
            | {:geoJson, boolean}
            | {:expireAfter, integer}
            | {:name, atom}

    @doc """
    Creates a new Index struct
    """
    @spec new(String.t(), [atom() | String.t()], [index_option()]) :: t()
    def new(name, fields, opts \\ [])
    def new(name, fields, opts) when is_atom(name), do: new(Atom.to_string(name), fields, opts)

    def new(name, fields, opts) when is_binary(name) and is_atom(fields),
      do: new(name, [fields], opts)

    def new(name, fields, opts) when is_binary(name) and is_list(fields) and is_list(opts) do
      keys = Keyword.merge(opts, collection_name: name, fields: fields)

      index = struct(__MODULE__, keys)
      %{index | name: index.name || default_index_name(index)}
    end

    defp default_index_name(index) do
      ["idx", index.collection_name, index.fields]
      |> List.flatten()
      |> Enum.map_join(
        "_",
        fn item ->
          item
          |> to_string()
          |> String.replace(~r"[^\w]", "_")
          |> String.replace_trailing("_", "")
        end
      )
    end
  end

  defmodule Collection do
    @moduledoc """
    Used internally by the `ArangoXEcto` migration.

    To define a collection in a migration, see `ArangoXEcto.Migration.collection/2`.

    The attributes in this struct are directly passed to the
    ArangoDB API for creation. No validation is done on the
    attributes and is left to the database to manage.
    """

    @enforce_keys [:name]
    defstruct [
      :name,
      :waitForSync,
      :schema,
      :keyOptions,
      :isSystem,
      :prefix,
      :cacheEnabled,
      :numberOfShards,
      :shardKeys,
      :replicationFactor,
      :writeConcern,
      :distributeShardsLike,
      :shardingStrategy,
      :smartJoinAttribute,
      type: 2
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            waitForSync: boolean() | nil,
            schema: map() | nil,
            keyOptions: map() | nil,
            isSystem: boolean() | nil,
            prefix: String.t() | nil,
            cacheEnabled: boolean() | nil,
            numberOfShards: integer() | nil,
            shardKeys: String.t() | nil,
            replicationFactor: integer() | nil,
            writeConcern: integer() | nil,
            distributeShardsLike: String.t() | nil,
            shardingStrategy: String.t() | nil,
            smartJoinAttribute: String.t() | nil,
            type: 2 | 3
          }

    @type collection_option ::
            {:waitForSync, boolean}
            | {:type, :document | :edge}
            | {:schema, map}
            | {:prefix, String.t()}
            | {:keyOptions, map}
            | {:cacheEnabled, boolean}
            | {:numberOfShards, integer}
            | {:isSystem, boolean()}
            | {:shardKeys, String.t()}
            | {:replicationFactor, integer}
            | {:writeConcern, integer}
            | {:distributeShardsLike, String.t()}
            | {:shardingStrategy, String.t()}
            | {:smartJoinAttribute, String.t()}

    @doc """
    Creates a new Collection struct
    """
    @spec new(String.t(), [collection_option()]) :: t()
    def new(name, opts \\ [])
    def new(name, opts) when is_atom(name), do: new(Atom.to_string(name), opts)

    def new(name, opts) when is_binary(name) and is_list(opts) do
      type = Keyword.get(opts, :type, :document)

      keys = Keyword.merge(opts, name: name, type: collection_type(type))

      struct(__MODULE__, keys)
    end

    defp collection_type(:document), do: 2
    defp collection_type(:edge), do: 3
  end

  defmodule Command do
    @moduledoc """
    Used internally by the `ArangoXEcto` migration.

    Represents the up and down of a reversible raw command defined by
    `ArangoXEcto.Migration.execute/1`. To make it reversible call `ArangoXEcto.Migration.execute/2`
    instead.
    """

    defstruct up: nil, down: nil
    @type t :: %__MODULE__{up: String.t(), down: String.t()}
  end

  @doc """
  Migration code to run immediately after the transaction is opened.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback after_begin() :: term

  @doc """
  Migration code to run immediately before the transaction is closed.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback before_commit() :: term
  @optional_callbacks after_begin: 0, before_commit: 0

  defmacro __using__(_) do
    quote location: :keep do
      import ArangoXEcto.Migration

      @disable_ddl_transaction false
      @before_compile ArangoXEcto.Migration
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __migration__ do
        [
          disable_ddl_transaction: @disable_ddl_transaction
        ]
      end
    end
  end

  @doc """
  Creates a collection or view.

  ## Collection Example

      create collection(:users) do
        add :first_name, :string
        add :last_name, :string, default: "Smith"

        timestamps()
      end

  ## View Example

      create view(:user_search) do
        add_sort(:created_at, :desc)
        add_sort(:first_name)

        add_store([:first_name, :last_name], :none)

        add_link("users", %Link{
          includeAllFields: true,
          fields: %{
            last_name: %Link{
              analyzers: [:identity, :text_en]
            }
          }
        })
      end
  """
  @spec create(Collection.t() | View.t(), do: Macro.t()) :: Macro.t()
  defmacro create(object, do: block) do
    expand_create(object, :create, block)
  end

  @doc """
  Creates a collection or view if it doesn't exist.

  Works just the same as `create/2` but will raise an error
  when the object already exists.
  """
  @spec create_if_not_exists(Collection.t() | View.t(), do: Macro.t()) :: Macro.t()
  defmacro create_if_not_exists(object, do: block) do
    expand_create(object, :create_if_not_exists, block)
  end

  defp expand_create(object, command, block) do
    quote do
      object = unquote(object)

      if object.__struct__ not in [Collection, View] do
        raise Ecto.MigrationError,
              "subcommands can only be passed when creating a Collection or a View, the following was passed: `#{object.__struct__}`"
      end

      Runner.start_command({unquote(command), ArangoXEcto.Migration.__prefix__(object)})
      unquote(block)
      Runner.end_command()

      object
    end
  end

  @doc """
  Alters a collection or view.

  ## Collection Examples 

      alter collection(:users) do
        add :middle_name, :string
        modify :people, :integer
        rename :people, to: :num
        remove :last_name
      end

  ## View Example

      alter view(:user_search) do
        add_link("new_test", %Link{
          includeAllFields: true,
          fields: %{
            last_name: %Link{
              analyzers: [:text_en]
            }
          }
        })

        remove_link("new_test")
      end
  """
  @spec alter(Collection.t() | View.t(), do: Macro.t()) :: Macro.t()
  defmacro alter(object, do: block) do
    quote do
      object = unquote(object)

      if object.__struct__ not in [Collection, View] do
        raise Ecto.MigrationError,
              "subcommands can only be passed when altering a Collection or a View, the following was passed: `#{object.__struct__}`"
      end

      Runner.start_command({:alter, ArangoXEcto.Migration.__prefix__(object)})
      unquote(block)
      Runner.end_command()
    end
  end

  @doc """
  Creates one of the following: 

    * an index
    * a collection with no schema
    * an analyzer

  When reversing (in a `change/0` running backwards), objects are only dropped
  if they exist, and no errors are raised. To enforce dropping an object, use
  `drop/1`.

  ## Examples

      create index("users", [:name])
      create collection("posts")
      create analyzer(:norm_en, :norm, [:frequency, :position], %{
          locale: "en",
          accent: false,
          case: :lower
        })

  """
  @spec create(object) :: object
        when object: Collection.t() | Index.t() | Analyzer.t()
  def create(%Collection{} = collection) do
    do_create(collection, :create)
  end

  def create(%Index{} = index) do
    Runner.execute({:create, __prefix__(index)})
    index
  end

  def create(%Analyzer{} = analyzer) do
    Runner.execute({:create, __prefix__(analyzer)})
    analyzer
  end

  @doc """
  Same as `create/1` except it will only create the object if it doesn't exist already.

  ## Examples

      create_if_not_exists index("users", [:name])

      create_if_not_exists collection("posts")

      create_if_not_exists analyzer(:norm_en, :norm, [:frequency, :position], %{
          locale: "en",
          accent: false,
          case: :lower
        })

  """
  @spec create_if_not_exists(object) :: object
        when object: Collection.t() | Index.t() | Analyzer.t()
  def create_if_not_exists(%Index{} = index) do
    Runner.execute({:create_if_not_exists, __prefix__(index)})
    index
  end

  def create_if_not_exists(%Collection{} = collection) do
    do_create(collection, :create_if_not_exists)
  end

  def create_if_not_exists(%Analyzer{} = analyzer) do
    Runner.execute({:create, __prefix__(analyzer)})
    analyzer
  end

  defp do_create(collection, command) do
    Runner.execute({command, __prefix__(collection), []})
    collection
  end

  @doc """
  Drops one of the following: 

    * an index
    * a collection
    * a view
    * an analyzer

  ## Examples 

      drop index("users", [:name])
      drop collection("posts")
      drop view("users_search")
      drop analyzer("users_search")

  """
  @spec drop(object) :: object
        when object: Collection.t() | Index.t() | View.t() | Analyzer.t()
  def drop(%mod{} = object) when mod in [Collection, Index, View, Analyzer] do
    Runner.execute({:drop, __prefix__(object)})

    object
  end

  @doc """
  Same as `drop/1` except only drops if it exists.

  Does not raise an error if the specified collection or index does not exist.

  ## Examples 

      drop_if_exists index("users", [:name])
      drop_if_exists collection("posts")
      drop_if_exists view("users_search")
      drop_if_exists analyzer("users_search")

  """
  @spec drop_if_exists(object) :: object
        when object: Collection.t() | Index.t() | View.t() | Analyzer.t()
  def drop_if_exists(%mod{} = object)
      when mod in [Collection, Index, View, Analyzer] do
    Runner.execute({:drop_if_exists, __prefix__(object)})

    object
  end

  @doc """
  Gets the migrator direction.
  """
  @spec direction :: :up | :down
  def direction do
    Runner.migrator_direction()
  end

  @doc """
  Gets the migrator repo.
  """
  @spec repo :: Ecto.Repo.t()
  def repo do
    Runner.repo()
  end

  @doc """
  Gets the migrator prefix.
  """
  def prefix do
    Runner.prefix()
  end

  @doc """
  Creates a collection struct that can be provided to one of the action functions.


  ## Options

  Accepts an options parameter as the third argument. For available keys please refer to the
  [ArangoDB API doc](https://www.arangodb.com/docs/stable/http/collection-creating.html).
  The following options differ slightly:

    * `:type` - accepts either `:document` or `:edge`. Default is `:document`.
    * `:prefix` - the prefix for the collection. This will be the prefix database used for the
      collection.

  ## Examples

      iex> collection("users")
      %ArangoXEcto.Migration.Collection{name: "users", type: 2)

      iex> collection("users", type: :edge)
      %ArangoXEcto.Migration.Collection{name: "users", type: 3)

      iex> collection("users", keyOptions: %{type: :uuid})
      %ArangoXEcto.Migration.Collection{name: "users", type: 2, keyOptions: %{type: :uuid})
  """
  @spec collection(String.t(), [Collection.collection_option()]) :: Collection.t()
  def collection(collection_name, opts \\ []),
    do: Collection.new(collection_name, opts)

  @doc """
  Creates an edge collection struct

  Same as passing `:edge` as the type to `collection/3`.
  """
  @spec edge(String.t(), [Collection.collection_option()]) :: Collection.t()
  def edge(edge_name, opts \\ []), do: collection(edge_name, Keyword.put(opts, :type, :edge))

  @doc """
  Creates an index struct that can be passed to an action function.

  Default index type is a hash. To change this pass the `:type` option in options.

  This will generate a name for the index if not provided. This allows for the dropping
  of the index.

  ## Options

  Options only apply to the creation of indexes and has no effect when using the `drop/1` function.

    * `:name` - The name of the index (usefull for phoenix constraints). Defaults to
    "idx*_*<collection>*_*<fields_separated_by_underscore>".
    * `:prefix` - the prefix for the collection. This will be the prefix database used for the
        index collection.
    * `:type` - The type of index to create
      * Accepts: `:fulltext`, `:geo`, `:hash`, `:persistent`, `:skiplist` or `:ttl`
    * `:unique` - If the index should be unique, defaults to false (hash, persistent & skiplist only)
    * `:sparse` - If index should be spares, defaults to false (hash, persistent & skiplist only)
    * `:deduplication` - If duplication of array values should be turned off, defaults to true (hash & skiplist only)
    * `:minLength` - Minimum character length of words to index (fulltext only)
    * `:geoJson` -  If a geo-spatial index on a location is constructed and geoJson is true, then the order
  within the array is longitude followed by latitude (geo only)
    * `:expireAfter` - Time in seconds after a document's creation it should count as `expired` (ttl only)

  ## Examples

  Create index on email field

      iex> index("users", [:email])
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email]}

  Create dual index on email and ph_number fields with a specified name

      iex> index("users", [:email, :ph_number], name: "my_cool_index")
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email, :ph_number], name:
      "my_cool_index"}

  Create unique email index

      iex> index("users", [:email], unique: true)
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email], unique: true}

  Create a geo index

      iex> index("users", [:coordinates], type: :geo)
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:coordinates], type: :geo}
  """
  @spec index(String.t(), [atom() | String.t()], [Index.index_option()]) :: Index.t()
  def index(collection_name, fields, opts \\ []), do: Index.new(collection_name, fields, opts)

  @doc """
  Shortcut for creating a unique index.

  Same as passing :unique as true to `index/3`. See `index/3` for more information.
  """
  @spec unique_index(String.t(), [atom() | String.t()], [Index.index_option()]) :: Index.t()
  def unique_index(collection, fields, opts \\ []) when is_list(opts) do
    index(collection, fields, [unique: true] ++ opts)
  end

  @doc """
  Creates a view struct that can be passed to an action function.

  This is similar to the `collection/2` function except its representation is for a view.

  ## Options

  Refer to the arangodb docs for more options. Available options are in `t:View.view_option/0`.

    * `:prefix` - the prefix for the view. This will be the prefix database used for the
        Arango search view.

  ## Examples

      iex> view("users_search")
      %ArangoXEcto.Migration.View{name: "users_search")

      iex> view("users_search", primarySortCompression: :none)
      %ArangoXEcto.Migration.View{name: "users_search", primarySortCompression: :none)
  """
  @spec view(atom() | String.t(), [View.view_option()]) :: View.t()
  defdelegate view(name, opts \\ []), to: View, as: :new

  @doc """
  Creates an analyzer struct that can be passed to an action function.

  ## Parameters

    * `:name` - the name of the analyzer to be created
    * `:type` - the type of the analyzer, available options are
      `t:ArangoXEcto.Migration.Analyzer.type/0`.
    * `:features` - a list of enabled features, available options are
      `t:ArangoXEcto.Migration.Analyzer.feature/0`.
    * `:properties` - additional options for the analyzer, dependant on the type. Refer to the
      ArangoDB docs.
  """
  @spec analyzer(atom() | String.t(), Analyzer.type(), [Analyzer.feature()], map(), Keyword.t()) ::
          Analyzer.t()
  defdelegate analyzer(name, type, features, properties \\ %{}, opts \\ []),
    to: Analyzer,
    as: :new

  @doc """
  Represents an analyzer for deletion.

  Creates an analyzer struct with only a name so that it can be used to delete an analyzer.
  """
  @spec analyzer(atom() | String.t()) :: Analyzer.t()
  def analyzer(name) when is_binary(name) or is_atom(name) do
    %Analyzer{name: name}
  end

  @doc """
  Executes arbitrary AQL.

  The argument is typically a string, containing the AQL command to be executed.

  You can also run arbitrary code as part of your migrations by supplying an anonymous function.
  This is advantageous as it defers the execution of the anonymous function until after the
  migration callback is terminated (see [Executing and flushing](#module-executing-and-flushing)).

  Reversible commands can be defined by calling `execute/2`.

  ## Examples

      execute "FOR u IN `users` RETURN u.name"

      execute(fn -> repo().update_all("posts", set: [published: true]) end)
  """
  @spec execute(String.t() | function()) :: :ok
  def execute(command) when is_binary(command) or is_function(command, 0) do
    Runner.execute(command)
  end

  @doc """
  Executes reversible AQL commands.

  This is useful for database-specific functionality that does not
  warrant special support in ArangoXEcto. The `execute/2` form avoids having
  having to define separate `up/0` and `down/0` blocks that each contain an `execute/1`
  expression.

  The allowed parameters are explained in `execute/1`.

  ## Examples

      defmodule MyApp.MyMigration do
        use ArangoXEcto.Migration

        def change do
          execute "FOR u IN `users` RETURN u", "FOR u IN `users` RETURN u"
          execute(&execute_up/0, &execute_down/0)
        end

        defp execute_up, do: repo().query!("'Up query …';", [], [log: :info])
        defp execute_down, do: repo().query!("'Down query …';", [], [log: :info])
      end
  """
  @spec execute(String.t() | function(), String.t() | function()) :: :ok
  def execute(up, down)
      when (is_binary(up) or is_function(up, 0) or is_list(up)) and
             (is_binary(down) or is_function(down, 0) or is_list(down)) do
    Runner.execute(%Command{up: up, down: down})
  end

  @doc """
  Adds a field when creating or altering a collection with subfields.

  This makes the field type an object in the JSON Schema with the sub fields and options. See
  `add/3` for available options for an object.

  ## Example

      add_embed :fields do
        add :name, :string
        add :type, :string
      end

      add_embed :likes, comment: "my likes" do
        add :type, :string
        add :number, :integer
      end
  """
  @spec add_embed(atom(), Keyword.t(), do: Macro.t()) :: Macro.t()
  defmacro add_embed(field, opts \\ [], do: block) when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:add_embed, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
  end

  @doc """
  Adds a field that has multiple instances of the object.

  This represents a list of objects. This essentially wraps `add_embed/3`'s JSON Schema output with
  an array so that multiple instances of the object is represented.
  """
  @spec add_embed_many(atom(), Keyword.t(), do: Macro.t()) :: Macro.t()
  defmacro add_embed_many(field, opts \\ [], do: block) when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:add_embed_many, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
  end

  @doc """
  Adds a field when creating or altering a collection.

  This function accepts certain JSON Schema types and depending on the type it will accept certain
  options. The available types and options can be found in the
  `ArangoXEcto.Migration.JsonSchema.convert/2` function.

  ## Examples

      create collection("posts") do
        add :title, :string, comment: "Some comment"
      end

      alter collection("posts") do
        add :summary, :string
        add :object, :map
        add :age, :integer, min: 18, max: 99
      end
  """
  @spec add(atom(), ArangoXEcto.Migration.JsonSchema.field(), Keyword.t()) :: :ok
  def add(field, type, opts \\ []) when is_atom(field) and is_list(opts) do
    validate_type!(type)
    Runner.subcommand({:add, field, type, opts})
  end

  @doc """
  Adds a field if it does not exist yet when altering a collection.

  This is identical to `add/3` except only creates it if it hasn't been already.

  This is not reversible as existence can't be known beforehand.

  ## Examples

      alter collection("posts") do
        add_if_not_exists :title, :string, comment: "Some comment"
      end
  """
  @spec add_if_not_exists(atom(), ArangoXEcto.Migration.JsonSchema.field(), Keyword.t()) :: :ok
  def add_if_not_exists(field, type, opts \\ []) when is_atom(field) and is_list(opts) do
    validate_type!(type)
    Runner.subcommand({:add_if_not_exists, field, type, opts})
  end

  @doc """
  Adds a primary sort to a view.

  This adds a sort to the view, refer to the [ArangoDB docs](https://docs.arangodb.com/3.11/index-and-search/arangosearch/arangosearch-views-reference/#view-properties).

  This accepts a field name and a sort direction (either `:asc` or `:desc`), defaults to `:asc`.
  """
  @spec add_sort(atom(), :asc | :desc) :: :ok
  def add_sort(field, direction \\ :asc) when is_atom(field) and direction in [:asc, :desc] do
    Runner.subcommand({:add_sort, field, direction})
  end

  @doc """
  Adds a stored value to a view.

  This adds a stored value to the view, refer to the [ArangoDB docs](https://docs.arangodb.com/3.11/index-and-search/arangosearch/arangosearch-views-reference/#view-properties).

  This accepts a field name and a compression (either `:lz4` or `:none`), defaults to `:lz4`.
  """
  @spec add_store(atom(), :none | :lz4) :: :ok
  def add_store(fields, compression \\ :lz4) when compression in [:none, :lz4] do
    Runner.subcommand({:add_store, List.wrap(fields), compression})
  end

  @doc """
  Adds a link to a view.

  Uses a `ArangoXEcto.View.Link` struct to define the link. See the module for more information.

  ## Example

      link "users", %Link{
        includeAllFields: true,
        fields: %{
          name: %Link{
            analyzers: [:text_en]
          }
        }
      }
  """
  @spec add_link(atom() | String.t(), ArangoXEcto.View.Link.t()) :: :ok
  def add_link(schema_name, link) when is_atom(schema_name),
    do: add_link(Atom.to_string(schema_name), link)

  def add_link(schema_name, %Link{} = link) when is_binary(schema_name) do
    validate_link!(link)
    Runner.subcommand({:add_link, schema_name, link})
  end

  @doc """
  Renames a collection, view or a collection field

  ## Examples

      # rename a collection
      rename collection("users"), to: collection("new_users")

      # rename a view
      rename view("user_search"), to: view("new_user_search")

      alter collection("users") do
        rename :name, to: :first_name
      end

  """
  @spec rename(object, to: object) :: object when object: Collection.t() | View.t() | atom()
  def rename(%Collection{} = collection_current, to: %Collection{} = collection_new) do
    Runner.execute({:rename, __prefix__(collection_current), __prefix__(collection_new)})
    collection_new
  end

  def rename(%View{} = view_current, to: %View{} = view_new) do
    Runner.execute({:rename, __prefix__(view_current), __prefix__(view_new)})
    view_new
  end

  def rename(current_field, to: new_field) when is_atom(current_field) and is_atom(new_field) do
    Runner.subcommand({:rename, current_field, new_field})
    new_field
  end

  @doc """
  Modifies the type of a field when altering a collection.

  This command is not reversible unless the `:from` option is provided. You want to specify all the
  necessary options and types so that it can be rolled back properly.

  See `add/3` for more information on supported types.

  ## Examples

      alter collection("users") do
        modify :name, :string
      end

      # Self rollback when using the :from option
      alter collection("users") do
        modify :name, :string, from: :integer
      end

      # Modify field with rollback options
      alter collection("users") do
        modify :name, :string, null: true, from: {:integer, null: false}
      end

  ## Options

  Options are the same as `add/3` but with the additional following option.

    * `:from` - specifies the current type and options of the field.
  """
  @spec modify(atom(), ArangoXEcto.Migration.JsonSchema.field(), Keyword.t()) :: :ok
  def modify(field, type, opts \\ []) when is_atom(field) and is_list(opts) do
    validate_type!(type)
    Runner.subcommand({:modify, field, type, opts})
  end

  @doc """
  Modifies a field when creating or altering a collection with subfields.

  See `modify/3` for options and more info.
  """
  @spec modify_embed(atom(), Keyword.t(), do: Macro.t()) :: Macro.t()
  defmacro modify_embed(field, opts \\ [], do: block) when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:modify_embed, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
  end

  @doc """
  Modifies a field when creating or altering many objects with subfields.

  See `modify_embed/3` for options and more info.
  """
  @spec modify_embed_many(atom(), Keyword.t(), do: Macro.t()) :: Macro.t()
  defmacro modify_embed_many(field, opts \\ [], do: block)
           when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:modify_embed_many, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
  end

  @doc """
  Removes a field when altering a collection.

  If it doesn't exist it will simply be ignored.

  This command is not reversible as Ecto does not know what type it should add
  the field back as. See `remove/3` as a reversible alternative.

  ## Examples

      alter collection("users") do
        remove :name
      end

  """
  @spec remove(atom()) :: :ok
  def remove(field) when is_atom(field) do
    Runner.subcommand({:remove, field})
  end

  @doc """
  Removes a field in a reversible way when altering a collection.

  `type` and `opts` are exactly the same as in `add/3`, and
  they are used when the command is reversed.

  ## Examples

      alter collection("users") do
        remove :name, :string, min_length: 4
      end

  """
  @spec remove(atom(), ArangoXEcto.Migration.JsonSchema.field(), Keyword.t()) :: :ok
  def remove(field, type, opts \\ []) when is_atom(field) do
    validate_type!(type)
    Runner.subcommand({:remove, field, type, opts})
  end

  @doc """
  Removes a field only if it exists in the schema

  `type` and `opts` are exactly the same as in `add/3`, and
  they are used when the command is reversed.

  ## Examples

      alter collection("users") do
        remove_if_exists :name, :string, min_length: 4
      end

  """
  @spec remove_if_exists(atom(), ArangoXEcto.Migration.JsonSchema.field(), Keyword.t()) :: :ok
  def remove_if_exists(field, type, opts \\ []) when is_atom(field) do
    validate_type!(type)
    Runner.subcommand({:remove_if_exists, field, type, opts})
  end

  @doc """
  Removes a link when altering a view.

  If it doesn't exist it will simply be ignored.

  This command is not reversible as Ecto does not know what type it should add
  the field back as. See `remove_link/2` as a reversible alternative.

  ## Examples

      alter view("user_search") do
        remove_link "users"
      end

  """
  @spec remove_link(atom() | String.t()) :: :ok
  def remove_link(schema_name) when is_binary(schema_name) or is_atom(schema_name) do
    Runner.subcommand({:remove_link, "#{schema_name}"})
  end

  @doc """
  Removes a link in a reversable way when altering a view.

  `link` is the same as in `add_link/2`.

  ## Examples

      alter view("user_search") do
        remove_link "users", %Link{
          includeAllFields: true,
          fields: %{
            last_name: %Link{
              analyzers: [:text_en]
            }
          }
        }
      end

  """
  @spec remove_link(atom() | String.t(), ArangoXEcto.View.Link.t()) :: :ok
  def remove_link(schema_name, link) when is_atom(schema_name),
    do: remove_link(Atom.to_string(schema_name), link)

  def remove_link(schema_name, %Link{} = link) when is_binary(schema_name) do
    validate_link!(link)
    Runner.subcommand({:remove_link, schema_name, link})
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamp fields.

  Those fields are of `:naive_datetime` type and by default cannot be null. A
  list of `opts` can be given to customize the generated fields.

  Following options will override the repo configuration specified by
  `:migration_timestamps` option.

  ## Options

    * `:inserted_at` - the name of the column for storing insertion times.
      Setting it to `false` disables the column.
    * `:updated_at` - the name of the column for storing last-updated-at times.
      Setting it to `false` disables the column.
    * `:type` - the type of the `:inserted_at` and `:updated_at` columns.
      Defaults to `:naive_datetime`.

    The rest of the options are passed to the fields

  """
  def timestamps(opts \\ []) when is_list(opts) do
    opts = Keyword.merge(Runner.repo_config(:migration_timestamps, []), opts)

    {type, opts} = Keyword.pop(opts, :type, :naive_datetime)
    {inserted_at, opts} = Keyword.pop(opts, :inserted_at, :inserted_at)
    {updated_at, opts} = Keyword.pop(opts, :updated_at, :updated_at)

    if inserted_at != false, do: add(inserted_at, type, opts)
    if updated_at != false, do: add(updated_at, type, opts)
  end

  @doc """
  Executes queued migration commands
  """
  defmacro flush do
    quote do
      if direction() == :down and not function_exported?(__MODULE__, :down, 0) do
        raise "calling flush() inside change when doing rollback is not supported."
      else
        Runner.flush()
      end
    end
  end

  @doc false
  def __prefix__(%{prefix: prefix} = module) do
    runner_prefix = Runner.prefix()

    cond do
      is_nil(prefix) ->
        prefix = runner_prefix || Runner.repo_config(:migration_default_prefix, nil)
        %{module | prefix: prefix}

      is_nil(runner_prefix) or runner_prefix == to_string(prefix) ->
        module

      true ->
        raise Ecto.MigrationError,
          message:
            "the :prefix option `#{prefix}` does not match the migrator prefix `#{runner_prefix}`"
    end
  end

  ###########
  # Helpers #
  ###########

  # Validation helpers
  defp validate_link!(%Link{} = link) do
    if Link.valid?(link) do
      :ok
    else
      raise Ecto.MigrationError, "the passed link is invalid got: #{inspect(link)}"
    end
  end

  defp validate_type!(type) when is_atom(type) do
    case Atom.to_string(type) do
      "Elixir." <> _ ->
        raise_invalid_migration_type!(type)

      _ ->
        :ok
    end
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_atom(subtype) do
    validate_type!(subtype)
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_tuple(subtype) do
    for t <- Tuple.to_list(subtype), do: validate_type!(t)
  end

  defp validate_type!(type) do
    raise_invalid_migration_type!(type)
  end

  defp raise_invalid_migration_type!(type) do
    raise ArgumentError, """
    invalid migration type: #{inspect(type)}. Expected one of:

      * an atom, such as :string
      * a tuple representing a composite type, such as {:array, :integer} or {:map, :string}

    Ecto types are automatically translated to JSON Schema types. All other types
    are sent to the database as is.

    Types defined through Ecto.Type or Ecto.ParameterizedType aren't allowed,
    use their underlying types instead.
    """
  end
end
