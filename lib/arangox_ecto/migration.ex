defmodule ArangoXEcto.Migration do
  @moduledoc """
  Defines Ecto Migrations for ArangoDB

  > ## NOTE {: .info}
  >
  > ArangoXEcto dynamically creates collections for you by default. Depending on your project
  > architecture you may decide to use static migrations instead in which case this module will be useful.

  Migrations must use this module, otherwise migrations will not work. To do this, replace
  `use Ecto.Migration` with `use ArangoXEcto.Migration`.

  Since ArangoDB is schemaless, no fields need to be provided, only the collection name. First create
  a collection struct using the `collection/3` function. Then pass the collection struct to the
  `create/1` function. To create indexes it is a similar process using the `index/3` function.

  **Order matters!!** Make sure you create collections before indexes and views, and analyzers before
  views if they are used. In general this is a good order to follow:

      Analyzers > Collections > Indexes > Views

  To drop the collection on a migration down, do the same as creation except use the `drop/1` function
  instead of the `create/1` function. Indexes are automatically removed when the collection is removed
  and cannot be deleted using the `drop/1` function.

  ## Example

      defmodule MyProject.Repo.Migrations.CreateUsers do
        use ArangoXEcto.Migration

        def up do
          create(MyProject.Analyzers)

          create(collection(:users))

          create(index("users", [:email]))

          create(MyProject.UsersView)
        end

        def down do
          drop(collection(:users))
        end
      end
  """

  require Logger

  alias ArangoXEcto.Migration.Runner

  @typedoc "All migration commands"
  @type command ::
          raw ::
          String.t()
          | {:create, Collection.t(), [collection_subcommand]}
          | {:create_if_not_exists, Collection.t(), [collection_subcommand]}
          | {:alter, Collection.t(), [collection_subcommand]}
          | {:drop, Collection.t()}
          | {:drop_if_exists, Collection.t()}
          | {:create, Index.t()}
          | {:create_if_not_exists, Index.t()}
          | {:drop, Index.t()}
          | {:drop_if_exists, Index.t()}

  @typedoc "All commands allowed within the block passed to `collection/2`"
  @type collection_subcommand ::
          {:add, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(), Keyword.t()}
          | {:add_if_not_exists, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:modify, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:remove, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:remove, field :: atom}
          | {:remove_if_exists, type :: Ecto.Type.t() | Reference.t() | binary()}

  defmodule View do
    @moduledoc """
    Represents a view module in ArangoDB
    """

    @enforce_keys [:module]
    defstruct [
      :module,
      :prefix
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Analyzer do
    @moduledoc """
    Represents a analyzer module in ArangoDB
    """

    @enforce_keys [:name, :type, :features]
    defstruct [
      :name,
      :properties,
      :type,
      :features,
      :prefix
    ]

    @type t :: %__MODULE__{}

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

    @doc """
    Creates a new Analyzer struct
    """
    @spec new(atom() | String.t(), type(), [feature()], map(), prefix: atom()) :: t()
    def new(name, type, features, properties \\ %{}, opts \\ []) do
      validate_name!(name)
      validate_features!(features)
      validate_properties!(properties, name, type)

      keys =
        [name: name, type: type, features: features, properties: properties]
        |> Keyword.merge(opts)

      struct(__MODULE__, keys)
    end

    @doc false
    @spec validate_name!(atom()) :: atom()
    def validate_name!(name) do
      unless is_atom(name) do
        raise ArgumentError, "the name for analyzer must be an atom, got: #{inspect(name)}"
      end
    end

    @valid_keys [:frequency, :norm, :position]

    @doc false
    @spec validate_features!([atom()]) :: [atom()]
    def validate_features!(features) do
      unless is_list(features) and Enum.all?(features, &Enum.member?(@valid_keys, &1)) do
        raise ArgumentError,
              "the features provided are invalid, only accepts keys [:frequency, :norm, :position], got: #{inspect(features)}"
      end
    end

    @doc false
    @spec validate_properties!([atom()], atom(), type()) :: [atom()]
    def validate_properties!(properties, name, type) do
      keys = valid_keys(type)

      Enum.all?(properties, fn {k, v} ->
        Enum.member?(keys, k) and valid_key?(k, v)
      end)
      |> unless do
        raise ArgumentError,
              "the properties provided for analyzer '#{name}' are invalid, only accepts keys #{inspect(keys)}, got: #{inspect(properties)}"
      end
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
  end

  defmodule Index do
    @moduledoc """
    Represents a collection index in ArangoDB

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

    @type t :: %__MODULE__{}

    @type index_option ::
            {:type, atom}
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
    def new(name, fields, opts \\ []) do
      keys =
        [collection_name: name, fields: fields]
        |> Keyword.merge(opts)

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
    Represent a collection in ArangoDB

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
      :type,
      :isSystem,
      :prefix,
      :cacheEnabled,
      :numberOfShards,
      :shardKeys,
      :replicationFactor,
      :writeConcern,
      :distributeShardsLike,
      :shardingStrategy,
      :smartJoinAttribute
    ]

    @type t :: %__MODULE__{}

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
    def new(name, opts \\ []) do
      type = Keyword.get(opts, :type, :document)

      keys =
        [name: name, type: collection_type(type)]
        |> Keyword.merge(opts)

      struct(__MODULE__, keys)
    end

    defp collection_type(:document), do: 2
    defp collection_type(:edge), do: 3
  end

  defmodule Command do
    @moduledoc """
    Represents the up and down of a reversible raw command.
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
  Creates a collection.

  The collection `:id` type will be `:binary_id`.

  ## Example

      create collection(:users) do
        add :first_name, :string
        add :last_name, :string, default: "Smith"

        timestamps()
      end
  """
  defmacro create(object, do: block) do
    expand_create(object, :create, block)
  end

  @doc """
  Creates a collection if it doesn't exist.

  Works just the same as `create/2` but will raise an error
  when the object already exists.
  """
  defmacro create_if_not_exists(object, do: block) do
    expand_create(object, :create_if_not_exists, block)
  end

  defp expand_create(object, command, block) do
    quote do
      collection = %Collection{} = unquote(object)
      Runner.start_command({unquote(command), ArangoXEcto.Migration.__prefix__(collection)})
      unquote(block)
      Runner.end_command()

      collection
    end
  end

  @doc """
  Alters a collection

  ## Examples 

      alter collection(:users) do
        add :middle_name, :string
        modify :people, :integer
        rename :people, to: :num
        remove :last_name
      end
  """
  defmacro alter(object, do: block) do
    quote do
      collection = %Collection{} = unquote(object)
      Runner.start_command({:alter, ArangoXEcto.Migration.__prefix__(collection)})
      unquote(block)
      Runner.end_command()
    end
  end

  @doc """
  Creates on of the following: 

    * an index
    * a collection with no schema

  When reversing (in a `change/0` running backwards), indexes are only dropped
  if they exist, and no errors are raised. To enforce dropping an index, use
  `drop/1`.

  ## Examples

      create index("users", [:name])
      create collection("posts")

  """
  def create(%Collection{} = collection) do
    do_create(collection, :create)
  end

  def create(%Index{} = index) do
    Runner.execute({:create, __prefix__(index)})
    index
  end

  def create(%mod{} = view_or_analyzer) when mod in [View, Analyzer] do
    Runner.execute({:create, __prefix__(view_or_analyzer)})
    mod
  end

  @doc """
  Creates a collection without a schema or an index if it doesn't exist already.

  ## Examples

      create_if_not_exists index("users", [:name])

      create_if_not_exists collection("posts")

  """
  def create_if_not_exists(%Index{} = index) do
    Runner.execute({:create_if_not_exists, __prefix__(index)})
  end

  def create_if_not_exists(%Collection{} = collection) do
    do_create(collection, :create_if_not_exists)
  end

  defp do_create(collection, command) do
    Runner.execute({command, __prefix__(collection), []})
  end

  @doc """
  Drops one of the following: 

    * an index
    * a collection

  ## Examples 

      drop index("users", [:name])
      drop collection("posts")

  """
  def drop(%mod{} = collection_or_index) when mod in [Collection, Index] do
    Runner.execute({:drop, __prefix__(collection_or_index)})

    collection_or_index
  end

  @doc """
  Drops a collection or index if it exists

  Does not raise an error if the specified collection or index does not exist.

  ## Examples 

      drop_if_exists index("users", [:name])
      drop_if_exists collection("posts")

  """
  def drop_if_exists(%mod{} = collection_or_index) when mod in [Collection, Index] do
    Runner.execute({:drop_if_exists, __prefix__(collection_or_index)})

    collection_or_index
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
  Creates a collection struct

  Used to in functions that perform actions on the database.

  Accepts a collection type parameter that can either be `:document` or `:edge`, otherwise it will
  raise an error. The default option is `:document`.


  ## Options

  Accepts an options parameter as the third argument. For available keys please refer to the [ArangoDB API doc](https://www.arangodb.com/docs/stable/http/collection-creating.html).

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
  Creates an index struct

  Default index type is a hash. To change this pass the `:type` option in options.

  This will generate a name for the index if not provided. This allows for the dropping
  of the index.

  ## Options

  Options only apply to the creation of indexes and has no effect when using the `drop/1` function.

  - `:type` - The type of index to create
    - Accepts: `:fulltext`, `:geo`, `:hash`, `:persistent`, `:skiplist` or `:ttl`
  - `:unique` - If the index should be unique, defaults to false (hash, persistent & skiplist only)
  - `:sparse` - If index should be spares, defaults to false (hash, persistent & skiplist only)
  - `:deduplication` - If duplication of array values should be turned off, defaults to true (hash & skiplist only)
  - `:minLength` - Minimum character length of words to index (fulltext only)
  - `:geoJson` -  If a geo-spatial index on a location is constructed and geoJson is true, then the order
  within the array is longitude followed by latitude (geo only)
  - `:expireAfter` - Time in seconds after a document's creation it should count as `expired` (ttl only)
  - `:name` - The name of the index (usefull for phoenix constraints)

  ## Examples

  Create index on email field

      iex> index("users", [:email])
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email]}

  Create dual index on email and ph_number fields

      iex> index("users", [:email, :ph_number])
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email, :ph_number]}

  Create unique email index

      iex> index("users", [:email], unique: true)
      %ArangoXEcto.Migration.Index{collection_name: "users", fields: [:email], unique: true}
  """
  @spec index(String.t(), [atom() | String.t()], [Index.index_option()]) :: Index.t()
  def index(collection_name, fields, opts \\ []), do: Index.new(collection_name, fields, opts)

  @doc """
  Shortcut for creating a unique index.

  See `index/3` for more information.
  """
  @spec unique_index(String.t(), [atom() | String.t()], [Index.index_option()]) :: Index.t()
  def unique_index(collection, fields, opts \\ []) when is_list(opts) do
    index(collection, fields, [unique: true] ++ opts)
  end

  @doc """
  Represents a view module
  """
  @spec view(module(), Keyword.t()) :: View.t()
  def view(module, opts \\ []) when is_list(opts) do
    keys = [module: module] |> Keyword.merge(opts)

    struct(View, keys)
  end

  @doc """
  Represents an analyzer module
  """
  defdelegate analyzer(name, type, features, properties, opts), to: Analyzer, as: :new

  @doc """
  Executes arbitrary AQL.

  The argument is typically a string, containing the AQL command to be executed.

  Reversible commands can be defined by calling `execute/2`.

  ## Examples

      execute "FOR u IN `users` RETURN u.name"
  """
  def execute(command) when is_binary(command) or is_function(command, 0) or is_list(command) do
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
  def execute(up, down)
      when (is_binary(up) or is_function(up, 0) or is_list(up)) and
             (is_binary(down) or is_function(down, 0) or is_list(down)) do
    Runner.execute(%Command{up: up, down: down})
  end

  @doc """
  Adds a field when creating or altering a collection with subfields.

  See `add/3` for options and more info.
  """
  defmacro add_embed(field, opts \\ [], do: block) when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:add_embed, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
  end

  @doc """
  Adds a field when creating or altering a collection.

  TODO: Add note about what types are accepted

  TODO: Update examples and options
  ## Examples

      create collection("posts") do
        add :title, :string, default: "Untitled"
      end

  ## Options

    * `:primary_key` - when `true`, marks this field as the primary key.
      If multiple fields are marked, a composite primary key will be created.
    * `:default` - the column's default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.
    * `:null` - determines whether the column accepts null values. When not specified,
      the database will use its default behaviour (which is to treat the column as nullable
      in most databases).
    * `:size` - the size of the type (for example, the number of characters).
      The default is no size, except for `:string`, which defaults to `255`.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
    * `:comment` - adds a comment to the added column.
    * `:after` - positions field after the specified one. Only supported on MySQL,
      it is ignored by other databases.
    * `:generated` - a string representing the expression for a generated column. See
      above for a comprehensive set of examples for each of the built-in adapters. If
      specified alongside `:start_value`/`:increment`, those options will be ignored.
    * `:start_value` - option for `:identity` key, represents initial value in sequence
      generation. Default is defined by the database.
    * `:increment` - option for `:identity` key, represents increment value for
      sequence generation. Default is defined by the database.

  """
  def add(field, type, opts \\ []) when is_atom(field) and is_list(opts) do
    validate_precision_opts!(opts, field)
    validate_type!(type)
    Runner.subcommand({:add, field, type, opts})
  end

  @doc """
  Renames a collection or a field

  ## Examples

      # rename a collection
      rename collection("users"), to: collection("new_users")

      alter collection("users") do
        rename :name, to: :first_name
      end

  """
  def rename(%Collection{} = collection_current, to: %Collection{} = collection_new) do
    Runner.execute({:rename, __prefix__(collection_current), __prefix__(collection_new)})
    collection_new
  end

  def rename(current_field, to: new_field) when is_atom(current_field) and is_atom(new_field) do
    Runner.subcommand({:rename, current_field, new_field})
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
  def remove(field) when is_atom(field) do
    Runner.subcommand({:remove, field})
  end

  @doc """
  Removes a field in a reversible way when altering a collection.

  `type` and `opts` are exactly the same as in `add/3`, and
  they are used when the command is reversed.

  ## Examples

      alter collection("users") do
        remove :name, :string, default: ""
      end

  """
  def remove(field, type, opts \\ []) when is_atom(field) do
    validate_type!(type)
    Runner.subcommand({:remove, field, type, opts})
  end

  @doc """
  Modifies the type of a field when altering a collection.

  This command is not reversible unless the `:from` option is provided.

  See `add/3` for more information on supported types.

  ## Examples

      alter collection("users") do
        modify :name, :string
      end

      # Self rollback when using the :from option
      alter collection("users") do
        modify :name, :string, from: :integer
      end

  ## Options

    * `:default` - changes the default value of the column.
    * `:from` - specifies the current type and options of the field.
    * `:comment` - adds a comment to the modified column.
  """
  def modify(field, type, opts \\ []) when is_atom(field) and is_list(opts) do
    validate_precision_opts!(opts, field)
    validate_type!(type)
    Runner.subcommand({:modify, field, type, opts})
  end

  @doc """
  Modifies a field when creating or altering a collection with subfields.

  See `modify/3` for options and more info.
  """
  defmacro modify_embed(field, opts \\ [], do: block) when is_atom(field) and is_list(opts) do
    quote do
      Runner.subcommand({:modify_embed, unquote(field), [], unquote(opts)})
      unquote(block)
      Runner.end_subcommand()

      :ok
    end
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
    * `:default` - the columns' default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.

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

  defp validate_precision_opts!(opts, field) when is_list(opts) do
    if opts[:scale] && !opts[:precision] do
      raise ArgumentError, "field #{Atom.to_string(field)} is missing precision option"
    end
  end
end
