defmodule ArangoXEcto.View do
  @moduledoc """
  ArangoSearch view module

  Defines a schema for a view to help create and manage Arango Search views.

  ## Creation

  Like for collections, the same static vs dynamic system is in place.
  If in dynamic mode and a collection that a view links to doesn't exist when querying,
  it will be created automatically. If in static mode an error will be raised if the the
  appropriate migration has not been made. Check out the `ArangoXEcto.Migration` module for
  more info.

  Like for collections, there is no check if a view exists when use the
  `ArangoXEcto.aql_query/4` function and will error, so make sure the view exists first.

  ### Example

    defmodule Something.UserSearch do
      use ArangoXEcto.View

      alias ArangoXEcto.View.Link

      view "user_search" do
        primary_sort :created_at, :desc
        primary_sort :name

        store_value [:email], :lz4
        store_value [:first_name, :last_name], :none

        link MyApp.Users, %Link{
          includeAllFields: true,
          fields: %{
            name: %Link{
              analyzers: [:text_en]
            }
          }
        }

        options  [
          primarySortCompression: :lz4
        ]
      end
    end

  ### Defining the analyzer module 

  **When in dynamic mode only** the analyzer module needs to be passed to the view so that 
  the analyzers will be automatically created. This option will be ignored in static mode. 
  You can pass the analyzer module by passing the module to the `:analyzer_module` option on 
  the use statement.

      use ArangoXEcto.View, analyzer_module: Something.Analyzers

  ## Querying

  Views essentially operate as virtual wrappers of Ecto Schemas. You can use them just like
  other schemas to query on and all the fields available are a culmination of the fields on the
  link schemas. This is how it works in the ArangoDB so to keep it true to function, it
  functions the same here.

  Querying is done exactly the same as a normal schema except the result will not be a struct. This is
  explained further below.

      iex> Repo.all(MyApp.UsersView)
      [%{first_name: "John", last_name: "Smith"}, _]

  ### Ecto Query Search

  Since the Arango Search function heavily relies on the AQL `SEARCH` operation it only makes
  sense for this to also work in Ecto Queries. You can find more info about this under `ArangoXEcto.Query.search/3`
  and `ArangoXEcto.Query.or_search/3`.

  The search operation functions the same as the `Ecto.Query.where/3` clause so that can be used for more reference.
  You can also use fragments to use special analyzers, an example is given below.

  > #### Note {: .info}
  >
  > You must import the ArangoXEcto.Query function to use the search query macro.

      iex> MyApp.UsersView |> search(gender: :male) |> Repo.all()
      [%{gender: :male}, ...]

      iex> from(MyApp.UsersView) |> search([uv], uv.gender == :female) |> Repo.all()
      [%{gender: :female}, ...]

      iex> UsersView |> search([uv], fragment("ANALYZER(? == ?, \"identity\")", uv.first_name, "John")) |> Repo.all()
      [%{first_name: "John"}]

  Unfortunately this won't work as an argument to the Ecto Query `from` macro (e.g. below) and will
  only work as above.

      # DO NOT USE THIS, IT WILL NOT WORK
      iex> from(uv in MyApp.UsersView, search: uv.first_name == "John")
      ArgumentError

  Of course you can also use AQL queries. Noting that you need to ensure the view is created already
  because it will not be checked.

    iex> ArangoXEcto.aql_query(Repo,
    ...>    "FOR uv IN @@view SEARCH ANALYZER(uv.first_name == @first_name, \"identity\") RETURN uv",
    ...>    "@view": UsersView.__view__(:name),
    ...>    first_name: "John"
    ...> )
    {:ok, [%{"first_name" => "John"}]}


  #### Sorting

  Since views work with ecto queries as per usual, you can use functions such as sort in Ecto queries.
  If you want to sort based on the BM25 score for example, you can use fragments like below.

      iex> UsersView
      ...> |> search(gender: :male)
      ...> |> order_by([uv], fragment("BM25(?)", uv))
      ...> |> select([uv], {uv.first_name, fragment("BM25(?)", uv)})
      [{"John", 1.8}, {"Bob", 1.8}]

  ### Loading results

  Due to how views function and the possibility of multiple types of returns, the result of a query
  cannot be automatically loaded to a struct with Ecto so you will have to use the `ArangoXEcto.load/2` function.
  It does still load the values using the field loaders to the correct type, so if you don't need to load
  it into a struct you can skip this.

      iex> Repo.all(MyApp.UsersView) |> ArangoXEcto.load(MyApp.User)
      [%User{first_name: "John", last_name: "Smith"}, _]

  Since you can have multiple different schemas linked, the `ArangoXEcto.load/2` function supports
  passing multiple module options that will match against the arango `_id` to load the correct module.

      iex> Repo.all(MyApp.UsersView) |> ArangoXEcto.load([MyApp.User, MyApp.Post])
      [%User{first_name: "John", last_name: "Smith"}, %Post{name: "abc"}]
  """
  @moduledoc since: "1.3.0"

  alias ArangoXEcto.View.Link

  @type name :: String.t()
  @type compression :: :lz4 | :none

  @doc false
  defmacro __using__(opts) do
    quote do
      import ArangoXEcto.View, only: [view: 2]

      @view_options nil

      Module.register_attribute(__MODULE__, :view_primary_sorts, accumulate: true)
      Module.register_attribute(__MODULE__, :view_stored_values, accumulate: true)
      Module.register_attribute(__MODULE__, :view_links, accumulate: true)
      Module.put_attribute(__MODULE__, :view_primary_sort_compression, :lz4)

      def __analyzer_module__ do
        Keyword.get(unquote(opts), :analyzer_module)
      end
    end
  end

  @doc """
  Defines a view with a view name and defenitions.

  Can only be defined once per view module.
  """
  defmacro view(name, do: block) do
    view(__CALLER__, name, block)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp view(caller, name, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :arango_view_defined) do
          raise "view schema already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        name = unquote(name)

        @arango_view_defined unquote(caller.line)

        try do
          import ArangoXEcto.View
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        def __view__(:name), do: unquote(name)
        def __view__(:primary_sort), do: @view_primary_sorts
        def __view__(:stored_values), do: @view_stored_values
        def __view__(:links), do: @view_links
        def __view__(:options), do: @view_options

        def __schema__(:source), do: unquote(name)
        def __schema__(:prefix), do: nil
        def __schema__(:loaded), do: %{}

        def __schema__(:query) do
          %Ecto.Query{
            from: %Ecto.Query.FromExpr{
              source: {unquote(name), __MODULE__}
            }
          }
        end

        for clauses <- ArangoXEcto.View.__schema__(@view_links),
            {args, body} <- clauses do
          def __schema__(unquote_splicing(args)), do: unquote(body)
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  Defines a primary sort field on the view.

  Only a field name is required but a direction can also be supplied. By default the direction will be ascending (:asc).

  This can be supplied more than once in a view block to enable multiple primary sorts.

  ## Parameters

      * `:field` - atom name of the field to be used as a primary sort
      * `:direction` - either `:asc` or `:desc` for sort direction
  """
  defmacro primary_sort(field, direction \\ :asc) do
    quote do
      field = unquote(field)
      direction = unquote(direction)

      unless is_atom(field) do
        raise ArgumentError,
              "the name for field must be an atom, got: #{inspect(field)}"
      end

      unless is_atom(direction) and direction in [:asc, :desc] do
        raise ArgumentError,
              "the direction for field `#{field}` must be an atom of either :asc or :desc, got: #{inspect(direction)}"
      end

      Module.put_attribute(__MODULE__, :view_primary_sorts, {unquote(field), unquote(direction)})
    end
  end

  @doc """
  Defines a stored value on the view.

  Only the fields used is required but the compression method can also be supplied. By default the compression will be :lz4.

  This can be supplied more than once in a view block to enable multiple stored value definitions.

  ## Parameters

      * `:fields` - a list of atoms for fields for the stored value
      * `:compression` - either `:none` or `:lz4` for compression, see `t:ArangoXEcto.View.compression/0`
  """
  defmacro store_value(fields, compression \\ :lz4) do
    quote do
      fields = unquote(fields)
      compression = unquote(compression)

      unless is_list(fields) and Enum.all?(fields, &is_atom/1) do
        raise ArgumentError,
              "the fields must be a list of atoms, got: #{inspect(fields)}"
      end

      unless is_atom(compression) and compression in [:none, :lz4] do
        raise ArgumentError,
              "the compression for stored value field with fields `#{inspect(fields)}` must be an atom of either :none or :lz4, got: #{inspect(compression)}"
      end

      Module.put_attribute(
        __MODULE__,
        :view_stored_values,
        {unquote(fields), unquote(compression)}
      )
    end
  end

  @doc """
  Defines a link field on the view.

  This can be supplied more than once in a view block to enable multiple link definitions.
  Each link can be of different documents or edges, this is sorted on querying as mentioned at the top of this module.

  Links are defined by the `ArangoXEcto.View.Link` module.

  ## Parameters

      * `:schema` - the module of the document or edge the link should be created on
      * `:link` - the link definition, see `ArangoXEcto.View.Link`
  """
  defmacro link(schema, link) do
    quote do
      schema = unquote(schema)
      link = unquote(link)

      unless is_atom(schema) and
               (ArangoXEcto.is_document?(schema) or ArangoXEcto.is_edge?(schema)) do
        raise ArgumentError,
              "the schema passed must be an Ecto schema, got: #{inspect(schema)}"
      end

      unless Link.valid?(link) do
        raise ArgumentError,
              "the link is invalid for field `#{schema}` got: #{inspect(link)}"
      end

      Module.put_attribute(
        __MODULE__,
        :view_links,
        {unquote(schema), unquote(link)}
      )
    end
  end

  @doc """
  Defines options for view creation.

  ## Options

  The available options are directly from the [ArangoDB View definition](https://www.arangodb.com/docs/stable/arangosearch-views.html).

      * `:consolidationIntervalMsec` - wait at least this many milliseconds between applying consolidationPolicy
        to consolidate View data store and possibly release space on the filesystem.
      * `:consolidationPolicy` - the consolidation policy to apply for selecting data store segment merge candidates.
      * `:commitIntervalMsec` - wait at least this many milliseconds between committing View data store changes
         and making documents visible to queries.
      * `:writebufferSizeMax` - maximum memory byte size per writer (segment) before a writer (segment) flush is triggered.
      * `:writebufferIdle` - maximum number of writers (segments) cached in the pool.
      * `:writebufferActive` - maximum number of concurrent active writers (segments) that perform a transaction.
        Other writers (segments) wait till current active writers (segments) finish.
      * `:cleanupIntervalStep` - waits at least this many commits between removing unused files in its data directory .
      * `:primarySortCompression` - defines how to compress the primary sort data (introduced in ArangoDB v3.7.0).
        See `t:ArangoXEcto.View.compression/0`.

        `:lz4` (default) - use LZ4 fast compression
        `:none` - disable compression to trade space for speed

  """
  defmacro options(attrs) do
    quote do
      attrs = unquote(attrs)

      with {:error, invalid_keys} <-
             Keyword.validate(attrs, [
               :consolidationIntervalMsec,
               :consolidationPolicy,
               :commitIntervalMsec,
               :writebufferSizeMax,
               :writebufferIdle,
               :writebufferActive,
               :cleanupIntervalStep,
               :primarySortCompression
             ]) do
        raise ArgumentError, "invalid option keys: #{inspect(invalid_keys)}"
      end

      Module.put_attribute(__MODULE__, :view_options, attrs)
    end
  end

  @doc """
  Generates the view definition

  This takes the macros that define the view and converts it into
  a definition for use on creation.
  """
  @spec definition(Module.t()) :: map()
  def definition(view) when is_atom(view) do
    if function_exported?(view, :__view__, 1) do
      opts = Enum.into(view.__view__(:options), %{})

      %{
        name: view.__view__(:name),
        type: "arangosearch",
        links: %{},
        primarySort: [],
        storedValues: []
      }
      |> add_links(view)
      |> add_primary_sort(view)
      |> add_stored_values(view)
      |> Map.merge(opts)
    else
      raise ArgumentError, "not a valid view schema"
    end
  end

  @doc false
  def __schema__(links) do
    {primary_keys, query_fields, fields, field_sources} =
      Enum.reduce(
        links,
        {MapSet.new(), MapSet.new(), %{}, %{}},
        fn {schema, _}, {primary_keys, query_fields, fields, field_sources} ->
          {new_fields, new_field_sources} = get_field_info(fields, field_sources, schema)

          {MapSet.union(primary_keys, MapSet.new(schema.__schema__(:primary_key))),
           MapSet.union(query_fields, MapSet.new(schema.__schema__(:query_fields))), new_fields,
           new_field_sources}
        end
      )

    [
      [
        {[:primary_key], MapSet.to_list(primary_keys)},
        {[:query_fields], MapSet.to_list(query_fields)},
        {[:hash], :erlang.phash2({primary_keys, query_fields})},
        {[:fields], Enum.map(fields, &elem(&1, 0))}
      ]
      | Ecto.Schema.__schema__(fields, field_sources, [], [], [])
    ]
  end

  ###########
  # Helpers #
  ###########

  defp get_field_info(fields, field_sources, schema) do
    Enum.reduce(schema.__schema__(:fields), {fields, field_sources}, fn field,
                                                                        {a_fields,
                                                                         a_field_sources} ->
      {Map.put_new(a_fields, field, schema.__schema__(:type, field)),
       Map.put_new(a_field_sources, field, schema.__schema__(:field_source, field))}
    end)
  end

  defp add_links(map, view) do
    view.__view__(:links)
    |> Enum.reduce(map, fn {schema, link}, acc ->
      put_in(acc, [:links, schema.__schema__(:source)], Link.to_map(link))
    end)
  end

  defp add_stored_values(map, view) do
    view.__view__(:stored_values)
    |> Enum.reduce(map, fn {fields, compression}, acc ->
      val = %{fields: fields, compression: compression}
      Map.update!(acc, :storedValues, &[val | &1])
    end)
  end

  defp add_primary_sort(map, view) do
    view.__view__(:primary_sort)
    |> Enum.reduce(map, fn {field, direction}, acc ->
      val = %{field: field, direction: direction}
      Map.update!(acc, :primarySort, &[val | &1])
    end)
  end
end
