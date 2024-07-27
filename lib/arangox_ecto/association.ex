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

    @impl true
    def struct(module, name, opts) do
      queryables = Keyword.fetch!(opts, :queryables)
      related = ArangoXEcto.Association.related_from_query(queryables, name)
      on_replace = Keyword.get(opts, :on_replace, :raise)

      related_key = :__id__

      unless on_replace in @on_replace_opts do
        raise ArgumentError,
              "invalid `:on_replace` option for #{inspect(name)}. " <>
                "The only valid options are: " <>
                Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
      end

      where = opts[:where] || []

      unless is_list(where) do
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

    @impl true
    def build(refl, owner, attributes) do
      refl
      |> build(owner)
      |> struct(attributes)
    end

    @impl true
    def joins_query(_assoc) do
      raise RuntimeError, "Joins not supported by edges, use AQL graph traversal"
    end

    @impl true
    def assoc_query(_assoc, _query, _value) do
      raise RuntimeError, "Ecto.assoc/3 not supported by edges, use AQL graph traversal"
    end

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

    @impl true
    def build(_assoc, _owner) do
      raise RuntimeError, "building assoc not supported for edges, use AQL graph traversal"
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
    Module.put_attribute(mod, :ecto_fields, {name, type})
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :ecto_struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError,
            "field/association #{inspect(name)} already exists on schema, " <>
              "you must either remove the deduplication or choose a different name"
    end

    Module.put_attribute(mod, :ecto_struct_fields, {name, assoc})
  end

  @doc false
  def related_from_query(queryables, name) when is_list(queryables) do
    cond do
      Keyword.keyword?(queryables) ->
        queryables

      Enum.all?(queryables, &is_atom/1) ->
        queryables

      true ->
        raise ArgumentError,
              "association #{inspect(name)} queryables must be a " <>
                "list of schemas or a keyword list of modules and fields"
    end
  end

  def related_from_query(queryables, _name) when is_atom(queryables), do: List.wrap(queryables)
end
