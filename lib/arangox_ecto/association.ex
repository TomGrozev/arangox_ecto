defmodule ArangoXEcto.Association do
  @moduledoc false
  require Ecto.Schema

  defmodule EdgeMany do
    @moduledoc """
    The association struct for a `edge_many` association.

    This is only to be used by an edge's `:from` and `:to` fields. This is
    essentially the same as a BelongsTo association but modified to allow mupltiple
    related fields.

    This is needed because relational databases don't have the same ability to
    have multiple types of relation to the same name field like graph edges.

    Note that this will still only have a cardinality of one. I.e. in an edge
    the `:from` field will still only reference one other schema but can
    multiple different types of schemas.

    The available fields are:

      * `cardinality` - The association cardinality, always `:one`
      * `field` - The name of the association field on the schema
      * `owner` - The schema where the association was defined
      * `owner_key` - The key on the `owner` schema used for the association
      * `related` - The schema that is associated
      * `related_key` - The key on the `related` schema used for the association
      * `queryables` - The real query to use for querying association
      * `defaults` - default fields used when building the association
      * `relationship` - The relationship to the specified schema, default `:parent`
      * `on_replace` - The action taken on associations when schema is replaced
    """
    @moduledoc since: "2.0.0"

    @behaviour Ecto.Association
    @on_replace_opts [:raise, :mark_as_invalid, :delete, :delete_if_exists, :nilify, :update]

    defstruct [
      :field,
      :owner,
      :related,
      :owner_key,
      :related_key,
      :queryables,
      :on_cast,
      :on_replace,
      where: [],
      cardinality: :one,
      relationship: :parent,
      unique: true,
      ordered: false
    ]

    @type t :: %__MODULE__{
            field: atom(),
            owner: atom(),
            related: [atom()],
            owner_key: atom(),
            related_key: atom(),
            queryables: [atom()],
            on_cast: nil | fun(),
            on_replace: atom(),
            where: Keyword.t(),
            cardinality: :one,
            relationship: :parent,
            unique: true,
            ordered: false
          }

    # coveralls-ignore-start
    @impl true
    def after_compile_validation(%{queryables: queryables, related_key: related_key}, env)
        when is_list(queryables) do
      Enum.find_value(queryables, fn queryable ->
        compiled = Ecto.Association.ensure_compiled(queryable, env)

        cond do
          compiled == :skip ->
            nil

          compiled == :not_found ->
            "association schema #{inspect(queryable)} does not exist"

          not function_exported?(queryable, :__schema__, 2) ->
            "associated module #{inspect(queryable)} is not an Ecto"

          is_nil(queryable.__schema__(:type, related_key)) ->
            "association schema #{inspect(queryable)} does not have field #{related_key}"

          true ->
            nil
        end
      end)
      |> case do
        nil ->
          :ok

        error ->
          {:error, error}
      end
    end

    # coveralls-ignore-stop

    @impl true
    def struct(module, name, opts) do
      queryables = Keyword.fetch!(opts, :queryables)
      related = ArangoXEcto.Association.related_from_query(queryables, name)
      on_replace = Keyword.get(opts, :on_replace, :raise)

      related_key = :__id__

      if on_replace not in @on_replace_opts do
        raise ArgumentError,
              "invalid `:on_replace` option for #{inspect(name)}. " <>
                "The only valid options are: " <>
                Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
      end

      where = opts[:where] || []

      if not is_list(where) do
        raise ArgumentError,
              "expected `:where` for #{inspect(name)} to be a keyword " <>
                "list, got: #{inspect(where)}"
      end

      %__MODULE__{
        field: name,
        owner: module,
        owner_key: Keyword.fetch!(opts, :key),
        related: related,
        related_key: related_key,
        queryables: queryables,
        on_replace: on_replace,
        where: where
      }
    end

    # coveralls-ignore-start
    @impl true
    def build(refl, owner, _attributes) do
      build(refl, owner)
    end

    @impl true
    def joins_query(_assoc) do
      raise RuntimeError, "Joins not supported by edges, use AQL graph traversal"
    end

    @impl true
    def assoc_query(_assoc, _query, _value) do
      raise RuntimeError, "Ecto.assoc/3 not supported by edges, use AQL graph traversal"
    end

    # coveralls-ignore-stop

    @impl true
    def preload_info(%{related_key: related_key} = refl) do
      {:assoc, refl, {0, related_key}}
    end

    @impl true
    def on_repo_change(%{on_replace: :nilify}, _, %{action: :replace}, _adapter, _opts) do
      {:ok, nil}
    end

    def on_repo_change(
          %{on_replace: :delete_if_exists} = refl,
          parent_changeset,
          %{action: :replace} = changeset,
          adapter,
          opts
        ) do
      on_repo_change(%{refl | on_replace: :delete}, parent_changeset, changeset, adapter, opts)
    rescue
      Ecto.StaleEntryError -> {:ok, nil}
    end

    def on_repo_change(
          %{on_replace: on_replace} = refl,
          parent_changeset,
          %{action: :replace} = changeset,
          adapter,
          opts
        ) do
      changeset =
        case on_replace do
          :delete -> %{changeset | action: :delete}
          :update -> %{changeset | action: :update}
        end

      on_repo_change(refl, parent_changeset, changeset, adapter, opts)
    end

    def on_repo_change(
          _refl,
          %{data: parent, repo: repo},
          %{action: action} = changeset,
          _adapter,
          opts
        ) do
      changeset = Ecto.Association.update_parent_prefix(changeset, parent)

      with {:ok, _} = ok <- apply(repo, action, [changeset, opts]) do
        if action == :delete, do: {:ok, nil}, else: ok
      end
    end

    ## Relation callbacks
    @behaviour Ecto.Changeset.Relation

    # coveralls-ignore-start
    @impl true
    def build(_assoc, _owner) do
      raise RuntimeError, "building assoc not supported for edges, use AQL graph traversal"
    end

    # coveralls-ignore-stop
  end

  defmodule Graph do
    @moduledoc """
    The association struct for a `graph` association.

    This is based off of the `many_to_many` relationship but modified to suit
    graph relations. This is uses graph traversal queries instead of the standard
    SQL format queries.

    This allows for multiple related schemas through the same edge. E.g.

        graph :friends, [Person, Pet], edge: Friends, on_replace: :delete

    Use the fields on the schema to identify which schema to use. If any of the fields in the list
    exists then it will use the key as the module.

        graph :friends, %{
            Person => [:first_name],
            Pet => [:name]
          },
          edge: Friends
      

    The available fields are:

      * `cardinality` - The association cardinality, always `:many`
      * `field` - The name of the association field on the schema
      * `owner` - The schema where the association was defined
      * `owner_key` - The key on the `owner` schema used for the association
      * `related` - The schema that is associated
      * `related_key` - The key on the `related` schema used for the association
      * `queryables` - The real query to use for querying association
      * `defaults` - default fields used when building the association
      * `relationship` - The relationship to the specified schema, default `:parent`
      * `on_replace` - The action taken on associations when schema is replaced
    """
    @moduledoc since: "2.0.0"

    import Ecto.Query
    import ArangoXEcto.Query, only: [graph: 5]

    @behaviour Ecto.Association

    @on_delete_opts [:nothing, :delete_all]
    @on_replace_opts [:raise, :mark_as_invalid, :delete]

    defstruct [
      :field,
      :owner,
      :related,
      :owner_key,
      :queryables,
      :mapping,
      :on_delete,
      :on_replace,
      :edge,
      :on_cast,
      :direction,
      relationship: :child,
      cardinality: :many,
      unique: false,
      where: [],
      ordered: false,
      preload_order: []
    ]

    @type t :: %__MODULE__{
            field: atom(),
            owner: atom(),
            related: [atom()],
            owner_key: atom(),
            queryables: [atom()],
            mapping: map(),
            on_delete: nil | fun(),
            on_cast: nil | fun(),
            on_replace: atom(),
            edge: module(),
            where: Keyword.t(),
            direction: :outbound | :inbound,
            cardinality: :many,
            relationship: :child,
            unique: false,
            ordered: false,
            preload_order: list()
          }

    # coveralls-ignore-start
    @impl true
    def after_compile_validation(%{queryables: queryables, edge: edge}, env) do
      case validate_queryables(queryables, edge, env) do
        nil ->
          :ok

        error ->
          {:error, error}
      end
    end

    defp validate_queryables(queryables, edge, env) do
      edge_compiled = Ecto.Association.ensure_compiled(edge, env)

      Enum.find_value(queryables, fn queryable ->
        compiled = Ecto.Association.ensure_compiled(queryable, env)

        cond do
          compiled == :skip ->
            nil

          compiled == :not_found ->
            "association schema #{inspect(queryable)} does not exist"

          not function_exported?(queryable, :__schema__, 2) ->
            "associated module #{inspect(queryable)} is not an Ecto"

          edge_compiled == :skip ->
            nil

          edge_compiled == :not_found ->
            ":edge schema #{inspect(edge)} does not exist"

          not function_exported?(edge, :__edge__, 0) ->
            ":edge module #{inspect(edge)} is not an Edge schema"

          true ->
            nil
        end
      end)
    end

    # coveralls-ignore-stop

    @impl true
    def struct(module, name, opts) do
      queryables = Keyword.fetch!(opts, :queryables)
      related = ArangoXEcto.Association.related_from_query(queryables, name)

      direction = Keyword.fetch!(opts, :direction)

      owner_key = :__id__

      edge =
        Keyword.get_lazy(opts, :edge, fn ->
          ArangoXEcto.edge_module(module, related, create: direction == :outbound)
        end)

      validate_edge(name, edge)

      if !Module.get_attribute(module, :ecto_fields)[owner_key] do
        raise ArgumentError,
              "schema does not have the field #{inspect(owner_key)} used by " <>
                "association #{inspect(name)}, this means it is likely not using ArangoXEcto.Schema"
      end

      on_delete = Keyword.get(opts, :on_delete, :nothing)
      on_replace = Keyword.get(opts, :on_replace, :raise)

      if on_delete not in @on_delete_opts do
        raise ArgumentError,
              "invalid `:on_delete` option for #{inspect(name)}. " <>
                "The only valid options are: " <>
                Enum.map_join(@on_delete_opts, ", ", &"`#{inspect(&1)}`")
      end

      if on_replace not in @on_replace_opts do
        raise ArgumentError,
              "invalid `:on_replace` option for #{inspect(name)}. " <>
                "The only valid options are: " <>
                Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
      end

      where = opts[:where] || []

      if !Keyword.keyword?(where) do
        raise ArgumentError,
              "expected `:where` for #{inspect(name)} to be a keyword " <>
                "list, got: #{inspect(where)}"
      end

      related_module = define_graph_relation_module(module, name, edge, related)

      %__MODULE__{
        field: name,
        owner: module,
        owner_key: owner_key,
        related: related_module,
        edge: edge,
        direction: direction,
        queryables: related,
        mapping: queryables,
        on_delete: on_delete,
        on_replace: on_replace,
        unique: Keyword.get(opts, :unique, false),
        where: where
      }
    end

    defp define_graph_relation_module(module, name, edge, queryables) do
      graph_mod =
        Atom.to_string(name)
        |> Macro.camelize()
        |> Kernel.<>("GraphRelation")
        |> String.to_atom()

      module_name = Module.concat(module, graph_mod)

      contents =
        quote do
          def __schema__(:primary_key) do
            Enum.flat_map(unquote(queryables), &(&1.__schema__(:primary_key) |> Enum.uniq()))
          end

          def __schema__(:source), do: unquote(edge).__schema__(:source)
          def __schema__(:prefix), do: unquote(edge).__schema__(:prefix)

          def __schema__(:type, :id), do: :binary_id
        end

      {:module, _, _, _} = Module.create(module_name, contents, Macro.Env.location(__ENV__))

      module_name
    end

    defp validate_edge(name, nil) do
      raise ArgumentError,
            "graph #{inspect(name)} had a nil :edge value, if not specified this will be auto generated"
    end

    defp validate_edge(_, edge) when is_atom(edge), do: :ok

    defp validate_edge(name, _edge) do
      raise ArgumentError,
            "graph #{inspect(name)} associations require the :edge option to be " <>
              "an atom (representing an edge schema)"
    end

    # coveralls-ignore-start
    @impl true
    def joins_query(_assoc) do
      raise RuntimeError, "joins not supported by graph relations, use AQL graph traversal"
    end

    # coveralls-ignore-stop

    def assoc_query(%{queryables: queryables} = refl, values) do
      assoc_query(refl, queryables, values)
    end

    @impl true
    def assoc_query(assoc, _, ids) do
      %{queryables: queryables, edge: edge, direction: direction} = assoc

      get_related(edge, queryables, ids, direction)
    end

    @impl true
    def build(refl, owner, attributes) do
      refl
      |> build(owner)
      |> struct(attributes)
    end

    @impl true
    def preload_info(refl) do
      # When preloading use the :_from in the edge and :__id__ in the schema
      # to filter out related entities to the owner structs we're preloading with.
      {:assoc, refl, {0, :_id}}
    end

    @impl true
    def on_repo_change(
          %{on_replace: :delete} = refl,
          parent_changeset,
          %{action: :replace} = changeset,
          adapter,
          opts
        ) do
      on_repo_change(refl, parent_changeset, %{changeset | action: :delete}, adapter, opts)
    end

    def on_repo_change(
          %{edge: edge},
          %{repo: repo, data: owner},
          %{action: :delete, data: related},
          adapter,
          opts
        ) do
      owner_value = dump!(:delete, edge, owner, adapter)
      related_value = dump!(:delete, edge, related, adapter)

      query =
        edge
        |> where([e], e._from == ^owner_value)
        |> where([e], e._to == ^related_value)

      query = %{query | prefix: owner.__meta__.prefix}
      repo.delete_all(query, opts)
      {:ok, nil}
    end

    def on_repo_change(
          %{field: field, edge: edge},
          %{repo: repo, data: owner} = parent_changeset,
          %{action: action} = changeset,
          adapter,
          opts
        ) do
      changeset = Ecto.Association.update_parent_prefix(changeset, owner)

      with {:ok, related} <- apply(repo, action, [changeset, opts]) do
        if insert_join?(parent_changeset, changeset, field) do
          owner_value = dump!(:delete, edge, owner, adapter)
          related_value = dump!(:delete, edge, related, adapter)
          data = %{_from: owner_value, _to: related_value}

          case insert_join(edge, parent_changeset, data, opts) do
            {:error, join_changeset} ->
              {:error,
               %{
                 changeset
                 | errors: join_changeset.errors ++ changeset.errors,
                   valid?: join_changeset.valid? and changeset.valid?
               }}

            _ ->
              {:ok, related}
          end
        else
          {:ok, related}
        end
      end
    end

    defp insert_join?(%{action: :insert}, _, _field), do: true
    defp insert_join?(_, %{action: :insert}, _field), do: true

    defp insert_join?(%{data: owner}, %{data: related}, field) do
      current_key = Map.fetch!(related, :__id__)

      not Enum.any?(Map.fetch!(owner, field), fn child ->
        Map.get(child, :__id__) == current_key
      end)
    end

    defp insert_join(edge, parent_changeset, data, opts) when is_atom(edge) do
      %{repo: repo, constraints: constraints, data: owner} = parent_changeset

      changeset =
        struct(edge)
        |> Map.merge(data)
        |> Ecto.Changeset.change()
        |> Map.put(:constraints, constraints)
        |> put_new_prefix(owner.__meta__.prefix)

      repo.insert(changeset, opts)
    end

    defp put_new_prefix(%{data: %{__meta__: %{prefix: prefix}}} = changeset, prefix),
      do: changeset

    defp put_new_prefix(%{data: %{__meta__: %{prefix: nil}}} = changeset, prefix),
      do: update_in(changeset.data, &Ecto.put_meta(&1, prefix: prefix))

    defp put_new_prefix(changeset, _), do: changeset

    defp field!(op, struct, field) do
      Map.get(struct, field) ||
        raise "could not #{op} join entry because `#{field}` is nil in #{inspect(struct)}"
    end

    defp dump!(action, edge, struct, _) when is_atom(edge) do
      field!(action, struct, :__id__)
    end

    ## Relation callbacks
    @behaviour Ecto.Changeset.Relation

    @impl true
    def build(%{queryables: [queryable]}, _owner) do
      struct(queryable)
    end

    # coveralls-ignore-start
    def build(%{owner: owner, field: field}, _) do
      raise RuntimeError,
            "cannot call build/2 on graph relation #{field} in module #{owner}. " <>
              "It is likely you used cast_assoc/3 instead of cast_graph/3."
    end

    # coveralls-ignore-stop

    ## On delete callbacks

    @doc false
    def delete_all(
          %{edge: edge, queryables: queryables, direction: direction},
          parent,
          repo_name,
          {%{opts: opts}, _}
        ) do
      if value = Map.get(parent, :__id__) do
        collections =
          Enum.map(queryables, & &1.__schema__(:source))

        direction_str =
          direction
          |> Atom.to_string()
          |> String.upcase()

        edge_source = edge.__schema__(:source)

        ArangoXEcto.aql_query(
          repo_name,
          """
          FOR v, e IN 1..1 #{direction_str} @id @edge OPTIONS {vertexCollections: @collections}
            REMOVE e._key in #{edge_source}
            #{remove_queries(collections)}
          """,
          [id: value, edge: edge_source, collections: collections],
          opts
        )
      end
    end

    defp remove_queries(collections) do
      Enum.map_join(collections, " ", fn collection ->
        "REMOVE v._key IN #{collection} OPTIONS { ignoreErrors: true }"
      end)
    end

    defp get_related(edge, queryables, ids, direction) do
      edge_source = edge.__schema__(:source)

      collections =
        Enum.map(queryables, & &1.__schema__(:source))

      maps = Enum.map(ids, &%{_id: &1})

      select_fields =
        for queryable <- queryables, field <- queryable.__schema__(:fields), reduce: [] do
          acc ->
            [queryable.__schema__(:field_source, field) | acc]
        end
        |> Enum.uniq()

      graph_direction(direction, maps, select_fields, edge_source, collections)
    end

    defp graph_direction(:inbound, maps, select_fields, edge_source, collections) do
      from(
        p in fragment("[?]", splice(^maps)),
        join:
          g in graph(1..1, :inbound, p._id, ^edge_source, vertexCollections: splice(^collections)),
        on: true,
        select: map(g, ^select_fields)
      )
    end

    defp graph_direction(:outbound, maps, select_fields, edge_source, collections) do
      from(
        p in fragment("[?]", splice(^maps)),
        join:
          g in graph(1..1, :outbound, p._id, ^edge_source,
            vertexCollections: splice(^collections)
          ),
        on: true,
        select: map(g, ^select_fields)
      )
    end
  end

  @doc """
  Indicates an edge many associations with one or more schemas.

  The current schema has an edge relationship with zero or one records of one or
  more other schemas. The other schema must have an `outgoing` or `incoming`
  association defined.

  This should only be used in edge schemas for relations of the `:from` and `:to` schemas.

  ## Parameters

    * `name` - The name of the related key
    * `queryables` - A module or list of modules that the edge is related to
    * `opts` - Options as below

  ## Options

    * `:key` - Sets the key field name, this is a required option.
    * `:references` - Sets the key on the other schema that is to be used
                      for association, defaults to: `:__id__`
    * `:on_replace` - The action taken on the association when the record is
                      replaced when casting or manipulating the parent changeset.
    * `:where` - A filter for the association. See "Filtering associations" in 
                `Ecto.Schema.has_many/3`.
  """
  defmacro edge_many(name, queryable, opts \\ []) do
    queryable = expand_literals(queryable, __CALLER__)

    quote do
      ArangoXEcto.Association.__edge_many__(
        __MODULE__,
        unquote(name),
        unquote(queryable),
        unquote(opts)
      )
    end
  end

  @valid_edge_many_options [:key, :references, :on_replace]

  @doc false
  def __edge_many__(mod, name, queryables, opts) do
    key_name = Keyword.fetch!(opts, :key)
    key_type = :binary_id

    check_options!(opts, @valid_edge_many_options, "edge_many/3")

    if key_name == name do
      raise ArgumentError,
            "key #{inspect(name)} must be distinct from corresponding " <>
              "association name"
    end

    Module.put_attribute(mod, :ecto_changeset_fields, {key_name, key_type})
    define_field(mod, key_name, key_type)

    struct =
      Ecto.Schema.association(
        mod,
        :one,
        name,
        ArangoXEcto.Association.EdgeMany,
        [queryables: List.wrap(queryables)] ++ opts
      )

    Module.put_attribute(mod, :ecto_changeset_fields, {name, {:assoc, struct}})
  end

  @doc """
  Indicates a graph association with one or more schemas.

  This association happens through an edge schema.

  ## Parameters

    * `name` - The name of the related key
    * `queryables` - A module or list of modules that the edge is related to
    * `direction` - The direction of the graph relation, either `:outbound` or `:inbound`
    * `opts` - Options as below

  ## Options

    * `:edge` - The edge schema to use, default will generate a new edge
    * `:on_replace` - The action taken on the association when the record is
                      replaced when casting or manipulating the parent changeset.
    * `:on_delete` - The action taken on the association when the record is
                      deleted when casting or manipulating the parent changeset.
    * `:where` - A filter for the association. See "Filtering associations" in 
                `Ecto.Schema.has_many/3`.
    * `:unique` - When true, checks if the associated entries are unique 
                whenever the association is cast or changed via the parent 
                record. For instance, it would verify that a given tag cannot 
                be attached to the same post more than once. This exists mostly 
                as a quick check for user feedback, as it does not guarantee 
                uniqueness in the Arango database.
  """
  defmacro graph(name, queryables, direction, opts \\ []) do
    queryables = expand_literals(queryables, __CALLER__)

    quote do
      ArangoXEcto.Association.__graph__(
        __MODULE__,
        unquote(name),
        unquote(queryables),
        unquote(direction),
        unquote(opts)
      )
    end
  end

  @valid_graph_options [:edge, :on_replace, :on_delete, :where, :unique]

  @doc false
  def __graph__(mod, name, queryables, direction, opts)
      when direction in [:outbound, :inbound] and (is_atom(queryables) or is_map(queryables)) do
    check_options!(opts, @valid_graph_options, "graph/3")

    struct =
      Ecto.Schema.association(
        mod,
        :many,
        name,
        ArangoXEcto.Association.Graph,
        [queryables: queryables, direction: direction] ++ opts
      )

    Module.put_attribute(mod, :ecto_changeset_fields, {name, {:assoc, struct}})
  end

  def __graph__(mod, name, queryables, _direction, _opts) do
    raise ArgumentError,
          "invalid associated schemas defined in #{mod} for " <>
            "graph relation #{name}. Expected a module name or a map, got: #{inspect(queryables)}"
  end

  defp expand_literals(ast, env) do
    if Macro.quoted_literal?(ast) do
      Macro.prewalk(ast, &expand_alias(&1, env))
    else
      ast
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:__schema__, 2}})

  defp expand_alias(other, _env), do: other

  defp check_options!(opts, valid, fun_arity) do
    case Enum.find(opts, fn {k, _} -> k not in valid end) do
      {k, _} -> raise ArgumentError, "invalid option #{inspect(k)} for #{fun_arity}"
      nil -> :ok
    end
  end

  defp define_field(mod, name, type) do
    put_struct_field(mod, name, nil)

    Module.put_attribute(mod, :ecto_query_fields, {name, type})
    Module.put_attribute(mod, :ecto_fields, {name, {type, :always}})
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :ecto_struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError,
            "field/association #{inspect(name)} already exists on schema, " <>
              "you must either remove the duplication or choose a different name"
    end

    Module.put_attribute(mod, :ecto_struct_fields, {name, assoc})
  end

  @doc false
  def related_from_query(queryables, name) when is_list(queryables) do
    if Enum.all?(queryables, &is_atom/1) do
      queryables
    else
      raise ArgumentError,
            "association #{inspect(name)} queryables must be a " <>
              "list of schemas or a map of modules and fields"
    end
  end

  def related_from_query(queryables, name) when is_map(queryables) do
    keys = Map.keys(queryables)

    if Enum.all?(keys, &is_atom/1) do
      keys
    else
      raise ArgumentError,
            "association #{inspect(name)} queryables must be " <>
              "a map with keys as schemas and value as a list of fields to be identified by."
    end
  end

  def related_from_query(queryables, _name) when is_atom(queryables), do: [queryables]

  def related_from_query(_queryables, name) do
    raise ArgumentError,
          "association #{inspect(name)} queryables must be a schema or " <>
            "for an edge relation it can also be a list. For a grapg relation it can be a map " <>
            "that has the schema as the key and the list of fields to identify it as the value."
  end
end
