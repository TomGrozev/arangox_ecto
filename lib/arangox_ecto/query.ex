import Kernel, except: [apply: 3]

defmodule ArangoXEcto.Query do
  @moduledoc """
  ArangoDB specific `Ecto.Query` functions.

  The `all/1`, `delete_all/1` and `update_all/1` functions in this module convert `Ecto.Query` 
  structs into AQL syntax.

  The Arango specific functions are available to support ArangoSearch questions and perform graph
  queries.

  ## ArangoSearch queries

  ArangoSearch queries can be performed through the `search/3` and `or_search/3` macros. For
  example, if you wanted to do a wildcard search for the title of your favorite movie you can do the
  following.

      from(MoviesView)
      |> search([mv], fragment("LIKE(?, ?)", mv.title, "%War%"))
      |> Repo.all()

  You can see that a fragment is used to incluse custom AQL. If you wanted to use a specific 
  analyzer, for example for case-insensitive searches, you could so using a fragment also like 
  below.

      from(MoviesView)
      |> search([mv], fragment("ANALYZER(LIKE(?, ?), \\"norm_en\\")", mv.title, "%war%"))
      |> Repo.all()

  ## Graph searches

  You can do graph queries inside Ecto queries. To do this you just use the `graph/5` macro
  provided. This will generate the required fragment to do graph queries.

  For example, take the following AQL query.

  ```
  FOR u IN 1..3 OUTBOUND "user/bob" friends
    RETURN u
  ```

  You can represent that using the following Ecto query. Note that a select is required since Ecto
  needs to know what fields to get when querying on a fragment.

      from(
        u in graph(1..3, :outbound, "user/bob", "friends"), 
          select: map(u, [:first_name, :last_name])
      )
      |> Repo.all()

  > #### Credit {: .info}
  >
  > This initial code for this module was used from 
  > https://github.com/ArangoDB-Community/arangodb_ecto/blob/master/lib/arangodb_ecto/query.ex.
  > Credit for the initial code goes to `mpoeter`. Updates were made since to enable additional
  > functionality and to work with the latest Ecto version.
  """

  alias Ecto.Query
  alias Ecto.Query.{BooleanExpr, Builder, JoinExpr, QueryExpr}

  @doc """
  Creates an AQL query to fetch all entries from the data store matching the given Ecto query.
  """
  @spec all(Query.t()) :: binary()
  def all(%Query{} = query) do
    sources = create_names(query)

    from = from(query, sources)
    join = join(query, sources)
    search = search_where(query, sources)
    where = where(query, sources)
    order_by = order_by(query, sources)
    offset_and_limit = offset_and_limit(query, sources)
    select = select(query, sources)

    IO.iodata_to_binary([from, join, search, where, order_by, offset_and_limit, select])
  end

  @doc """
  Creates an AQL query to delete all entries from the data store matching the given Ecto query.
  """
  @spec delete_all(Query.t()) :: binary()
  def delete_all(query) do
    ensure_not_view(query)

    sources = create_names(query)

    from = from(query, sources)
    join = join(query, sources)
    where = where(query, sources)
    order_by = order_by(query, sources)
    offset_and_limit = offset_and_limit(query, sources)
    remove = remove(query, sources)
    return = returning("OLD", query, sources)

    IO.iodata_to_binary([from, join, where, order_by, offset_and_limit, remove, return])
  end

  @doc """
  Creates an AQL query to update all entries from the data store matching the given Ecto query.
  """
  @spec update_all(Query.t()) :: binary()
  def update_all(query) do
    ensure_not_view(query)

    sources = create_names(query)

    from = from(query, sources)
    join = join(query, sources)
    where = where(query, sources)
    order_by = order_by(query, sources)
    offset_and_limit = offset_and_limit(query, sources)
    update = update(query, sources)
    return = returning("NEW", query, sources)

    IO.iodata_to_binary([from, join, where, order_by, offset_and_limit, update, return])
  end

  @doc """
  An AND search query expression.

  Extention to the `Ecto.Query` api for arango searches.

  The expression syntax is exactly the same as the regular `Ecto.Query.where/3` clause.
  Refer to that for more info on syntax or for advanced AQL queries see the section below.

  You will need to import this function like you do for `Ecto.Query`.

  ## Implementation

  This will store the search in the Ecto query `where` clause
  with a custom search operation. This is to prevent having to create a seperate query
  type. When converting the Ecto query to an AQL query, this is caught and changed
  into an AQL `SEARCH` expression.

  ## Using Analyzers and advanced AQL

  To save having to learn some new kind of query format for so many different possible search
  scenarios, you can just use AQL directly in. This is powered by the `Ecto.Query.API.fragment/1`
  function.

  Below is an example of how you can implement using a custom analyzer:

      from(UsersView)
      |> search([uv], fragment("ANALYZER(? == ?, \\"identity\\")", uv.first_name, "John"))
      |> Repo.all()

  """
  @doc since: "1.3.0"
  defmacro search(query, binding \\ [], expr) do
    query = build_search(:and, query, binding, expr, __CALLER__)

    query
  end

  @doc """
  A OR search query expression.

  Extention to the `Ecto.Query` api for arango searches.

  This function is the same as `ArangoXEcto.Query.search/3` except implements as an or clause.
  This also follows the same syntax as the `Ecto.Query.or_where/3` function.
  """
  @doc since: "1.3.0"
  defmacro or_search(query, binding \\ [], expr) do
    query = build_search(:or, query, binding, expr, __CALLER__)

    query
  end

  @doc false
  @spec apply(Ecto.Queryable.t(), :where, term) :: Ecto.Query.t()
  def apply(query, _, %{expr: true}) do
    query
  end

  def apply(%Ecto.Query{wheres: wheres} = query, :where, expr) do
    %{query | wheres: wheres ++ [expr]}
  end

  def apply(query, kind, expr) do
    apply(Ecto.Queryable.to_query(query), kind, expr)
  end

  @doc """
  Query an ArangoDB graph

  This is a helper around searching a graph. This essentially generates a fragment that is used in
  the from or join part of the Ecto query.

  You **MUST** provide a select in the query, otherwise an error be raised since Ecto can't work out
  what fields to use when a fragment is used.

  There is a limitiation that you can't use the `Ecto.Query.API.struct/2` function since the query
  is a fragment. If you need to load your results into a struct then you can use the
  `ArangoXEcto.load/2` function.

  ## Example

  For example, lets take the following query.

  ```
  FOR u IN 1..3 OUTBOUND "user/bob" friends
    RETURN u
  ```

  You can represent that using the following Ecto query. Note that like you would in any other Ecto
  query, you need to pin any variables used.

      from(
        u in graph(1..3, :outbound, "user/bob", "friends"), 
          select: map(u, [:first_name, :last_name])
      )
      |> Repo.all()

  ## Providing options

  You can also provide a keyword list as options as the last parameter to the macro.

  ```
  FOR u IN 1..3 OUTBOUND "user/bob" friends OPTIONS { vertexCollections: ["users"] }
    RETURN u
  ```

  This can be done using like the following.

      from(u in graph(1..3, :outbound, "user/bob", "friends", vertexCollections: ["users"]))
      |> select([u], map(u, [:first_name, :last_name]))
      |> Repo.all()

  ## Dynamically selecting fields

  If you want to select all of the fields on a struct you can use the following code and pin the
  `select_fields` variable. Replace the `User` schema with the schema in question.

      select_fields = Enum.map(User.__schema__(:fields), &User.__schema__(:field_source, &1))
  """
  @doc since: "2.0.0"
  @spec graph(Range.t(), :inbound | :outbound | :any, Macro.t(), Macro.t(), Keyword.t()) ::
          Macro.t()
  defmacro graph(range, direction, source, edge_graph, opts \\ [])

  defmacro graph({:.., _, [min, max]}, direction, source, edge_graph, opts) do
    if min < 0 or max < min do
      raise ArgumentError,
            "graph range min must be positive and max must be greater or equal to the min"
    end

    if not match?({:^, _, _}, direction) and direction not in [:inbound, :outbound, :any] do
      raise ArgumentError,
            "graph direction can only be :inbound, :outbound or :any"
    end

    direction =
      if is_atom(direction) do
        Atom.to_string(direction) |> String.upcase()
      else
        direction
      end

    query_string =
      [
        "#{min}..#{max}",
        quote(do: unquote(direction)),
        "?",
        "?"
      ]
      |> Enum.intersperse(" ")
      |> add_opts(opts)
      |> IO.iodata_to_binary()

    args =
      [query_string, source, edge_graph, Keyword.values(opts)]
      |> List.flatten()

    quote do: fragment(unquote_splicing(args))
  end

  defmacro graph(_, _, _, _, _) do
    raise ArgumentError,
          "graph can only have an inbound or outbound direction"
  end

  defp add_opts(query, []), do: query

  defp add_opts(query, opts) do
    [
      query,
      " OPTIONS {",
      Enum.map(opts, fn {k, v} -> "#{k}: #{value_input(v)}" end),
      "}"
    ]
  end

  defp value_input({:splice, _, _}), do: "[?]"
  defp value_input(_), do: "?"

  #
  # Helpers
  #

  defp ensure_not_view(%{sources: sources}) do
    sources
    |> Tuple.to_list()
    |> Enum.any?(fn {_, schema, _} -> ArangoXEcto.view?(schema) end)
    |> if do
      raise ArgumentError, "queries containing views cannot be update or delete operations"
    end
  end

  defp build_search(op, query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, acc}} = Builder.Filter.escape(:search, expr, 0, binding, env)

    params = Builder.escape_params(params)
    subqueries = Enum.reverse(acc.subqueries)

    expr =
      quote do: %Ecto.Query.BooleanExpr{
              expr: unquote(expr),
              op: unquote(search_op(op)),
              params: unquote(params),
              subqueries: unquote(subqueries),
              file: unquote(env.file),
              line: unquote(env.line)
            }

    Builder.apply_query(query, __MODULE__, [:where, expr], env)
  end

  defp search_op(:and), do: :search_and
  defp search_op(:or), do: :search_or

  defp create_names(%{sources: nil, from: %{source: {source, mod}}} = query) do
    query
    |> Map.put(:sources, {{source, mod, nil}})
    |> create_names()
  end

  defp create_names(%{sources: sources}) do
    create_names(sources, 0, tuple_size(sources), 0) |> List.to_tuple()
  end

  defp create_names(sources, pos, limit, acc) when pos < limit do
    {current, count} =
      case elem(sources, pos) do
        {:fragment, _, _} = frag ->
          {processed_frag, new_acc} = fragment_with_count(frag, acc)
          name = ["frag", Integer.to_string(pos)]
          {{expr(processed_frag, sources, nil), name, nil}, new_acc}

        {coll, schema, _} ->
          stripped_coll = String.replace(coll, ~r/[^A-Za-z]/, "")
          name = [String.first(stripped_coll), Integer.to_string(pos)]
          {{quote_collection(coll), name, schema}, acc}

        %Ecto.SubQuery{} ->
          raise "Subqueries are not supported."
      end

    [current | create_names(sources, pos + 1, limit, count)]
  end

  defp create_names(_sources, pos, pos, _) do
    []
  end

  defp fragment_with_count(frag, count) do
    Macro.prewalk(frag, 0, fn
      {:^, meta, [idx]}, acc -> {{:^, meta, [idx + count]}, acc + idx + count}
      {:splice, _, [_, len]} = ast, acc -> {ast, acc + len}
      other, acc -> {other, acc}
    end)
  end

  defp from(%Query{from: from} = query, sources) do
    {coll, name} = get_source(query, sources, 0, from)
    ["FOR ", name, " IN " | coll]
  end

  defp join(%Query{joins: []}, _sources), do: []

  defp join(%Query{joins: joins} = query, sources) do
    [
      ?\s
      | intersperse_map(joins, ?\s, fn %JoinExpr{
                                         on: %QueryExpr{expr: expr},
                                         qual: qual,
                                         ix: ix,
                                         source: source
                                       } ->
          {join, name} = get_source(query, sources, ix, source)
          # [join_qual(qual), join, " AS ", name, " FILTER " | expr(expr, sources, query)]
          if qual != :inner, do: raise("Only inner joins are supported.")
          ["FOR ", name, " IN ", join, " FILTER " | expr(expr, sources, query)]
        end)
    ]
  end

  defp search_where(%Query{wheres: wheres} = query, sources) do
    wheres = Enum.filter(wheres, fn %{op: op} -> op in [:search_and, :search_or] end)

    boolean(" SEARCH ", wheres, sources, query)
  end

  defp where(%Query{wheres: wheres} = query, sources) do
    wheres = Enum.filter(wheres, fn %{op: op} -> op in [:and, :or] end)

    boolean(" FILTER ", wheres, sources, query)
  end

  defp order_by(%Query{order_bys: []}, _sources), do: []

  defp order_by(%Query{order_bys: order_bys} = query, sources) do
    [
      " SORT "
      | intersperse_map(order_bys, ", ", fn %QueryExpr{expr: expr} ->
          intersperse_map(expr, ", ", &order_by_expr(&1, sources, query))
        end)
    ]
  end

  defp order_by_expr({dir, expr}, sources, query) do
    str = expr(expr, sources, query)

    case dir do
      :asc -> str
      :desc -> [str | " DESC"]
    end
  end

  defp offset_and_limit(%Query{offset: nil, limit: nil}, _sources), do: []

  # limit can either be a QueryExpr or a LimitExpr
  defp offset_and_limit(%Query{offset: nil, limit: %{expr: expr}} = query, sources) do
    [" LIMIT " | expr(expr, sources, query)]
  end

  defp offset_and_limit(%Query{offset: %QueryExpr{expr: _}, limit: nil} = query, _) do
    error!(query, "offset can only be used in conjunction with limit")
  end

  # limit can either be a QueryExpr or a LimitExpr
  defp offset_and_limit(
         %Query{offset: %QueryExpr{expr: offset_expr}, limit: %{expr: limit_expr}} = query,
         sources
       ) do
    [" LIMIT ", expr(offset_expr, sources, query), ", ", expr(limit_expr, sources, query)]
  end

  defp remove(%Query{from: from} = query, sources) do
    {coll, name} = get_source(query, sources, 0, from)
    [" REMOVE ", name, " IN " | coll]
  end

  defp update(%Query{from: from} = query, sources) do
    {coll, name} = get_source(query, sources, 0, from)
    fields = update_fields(query, sources)
    [" UPDATE ", name, " WITH {", fields, "} IN " | coll]
  end

  defp returning(_, %Query{select: nil}, _sources), do: []

  defp returning(version, query, sources) do
    {source, _, schema} = elem(sources, 0)
    select(query, {{source, version, schema}})
  end

  defp select(%Query{select: nil}, _sources), do: [" RETURN []"]

  defp select(%Query{select: %{fields: fields}, distinct: distinct, from: from} = query, sources),
    do: select_fields(fields, distinct, from, sources, query)

  defp select_fields(fields, distinct, _from, sources, query) do
    {collect, values} =
      fields
      |> count_fields()
      |> get_collect_or_fields(fields, sources, query)

    [collect | [" RETURN ", distinct(distinct, sources, query), "[ ", values | " ]"]]
  end

  defp count_fields(fields) do
    Enum.reduce(fields, {0, 0}, fn
      {:count, _, _}, {c, f} -> {c + 1, f}
      _, {c, f} -> {c, f + 1}
    end)
  end

  defp get_collect_or_fields({1, 0}, [{:count, _, value}], sources, _query),
    do: {count_field(value, sources), [count_name(value, sources)]}

  defp get_collect_or_fields({0, f}, fields, sources, query) when f > 0 do
    values =
      intersperse_map(fields, ", ", fn
        {_key, value} ->
          [expr(value, sources, query)]

        value ->
          [expr(value, sources, query)]
      end)

    {[], values}
  end

  defp get_collect_or_fields({0, 0}, _fields, _sources, _query) do
    {[], ["1"]}
  end

  defp get_collect_or_fields({c, _}, _fields, _sources, query) when c > 1,
    do: raise(Ecto.QueryError, message: "can only have one field with count", query: query)

  defp get_collect_or_fields({c, f}, _fields, _sources, query) when f > 0 and c > 0,
    do:
      raise(Ecto.QueryError,
        message: "can't have count fields and non count fields together (use raw AQL for this)",
        query: query
      )

  defp count_name([], _sources), do: "collection_count"
  defp count_name([val], sources), do: count_name(val, sources)
  defp count_name([val, _], sources), do: count_name(val, sources)

  defp count_name({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources) do
    name = name_from_sources(sources, idx)
    [name, ?_, Atom.to_string(field)]
  end

  defp count_field([], _sources), do: [" COLLECT WITH COUNT INTO collection_count"]

  defp count_field(field, sources),
    do: [" COLLECT ", ["WITH COUNT INTO ", count_name(field, sources)]]

  defp update_fields(%Query{from: from, updates: updates} = query, sources) do
    {_from, name} = get_source(query, sources, 0, from)

    fields =
      for(
        %{expr: expr} <- updates,
        {op, kw} <- expr,
        {key, value} <- kw,
        do: update_op(op, name, quote_name(key), value, sources, query)
      )

    Enum.intersperse(fields, ", ")
  end

  defp kv_list(key, value) do
    [key, ": " | value]
  end

  defp update_op(cmd, name, quoted_key, value, sources, query) do
    value = update_op_value(cmd, name, quoted_key, value, sources, query)
    kv_list(quoted_key, value)
  end

  defp update_op_value(:set, _name, _quoted_key, value, sources, query),
    do: expr(value, sources, query)

  defp update_op_value(:inc, name, quoted_key, value, sources, query),
    do: [name, ?., quoted_key, " + " | expr(value, sources, query)]

  defp update_op_value(:push, name, quoted_key, value, sources, query),
    do: ["PUSH(", name, ?., quoted_key, ", ", expr(value, sources, query), ")"]

  defp update_op_value(:pull, name, quoted_key, value, sources, query),
    do: ["REMOVE_VALUE(", name, ?., quoted_key, ", ", expr(value, sources, query), ", 1)"]

  defp update_op_value(cmd, _name, _quoted_key, _value, _sources, query),
    do: error!(query, "Unknown update operation #{inspect(cmd)} for AQL")

  defp distinct(nil, _sources, _query), do: []
  defp distinct(%QueryExpr{expr: true}, _sources, _query), do: "DISTINCT "
  defp distinct(%QueryExpr{expr: false}, _sources, _query), do: []

  defp distinct(%QueryExpr{expr: exprs}, _sources, query) when is_list(exprs) do
    error!(query, "DISTINCT with multiple fields is not supported by AQL")
  end

  defp get_source(query, sources, ix, source) do
    {expr, name, _schema} = elem(sources, ix)
    {expr || paren_expr(source, sources, query), name}
  end

  defp boolean(_name, [], _sources, _query), do: []

  defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
    [
      name,
      Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
        %BooleanExpr{expr: expr, op: op}, {op, acc} ->
          {op, [acc, operator_to_boolean(op) | paren_expr(expr, sources, query)]}

        %BooleanExpr{expr: expr, op: op}, {_, acc} ->
          {op, [?(, acc, ?), operator_to_boolean(op) | paren_expr(expr, sources, query)]}
      end)
      |> elem(1)
    ]
  end

  defp operator_to_boolean(:and), do: " && "
  defp operator_to_boolean(:search_and), do: " && "
  defp operator_to_boolean(:or), do: " || "
  defp operator_to_boolean(:search_or), do: " || "

  defp paren_expr(expr, sources, query) do
    [?(, expr(expr, sources, query), ?)]
  end

  #
  # Expressions
  #

  binary_ops = [
    ==: " == ",
    !=: " != ",
    <=: " <= ",
    >=: " >= ",
    <: " < ",
    >: " > ",
    and: " && ",
    or: " || ",
    like: " LIKE "
  ]

  @binary_ops Keyword.keys(binary_ops)

  Enum.map(binary_ops, fn {op, str} ->
    defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

  defp expr({:^, [], [idx]}, _sources, _query) do
    [?@ | Integer.to_string(idx + 1)]
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
       when is_atom(field) do
    name = name_from_sources(sources, idx)
    [name, ?. | quote_name(field)]
  end

  defp expr({:&, _, [idx]}, sources, _query) do
    [name_from_sources(sources, idx)]
  end

  defp expr({:&, _, [idx, fields, _counter]}, sources, query) do
    {source, name, schema} = elem(sources, idx)

    if (is_nil(schema) and is_nil(fields)) or schema == :fragment do
      error!(
        query,
        "ArangoDB does not support selecting all fields from #{source} without a schema. " <>
          "Please specify a schema or specify exactly which fields you want to select"
      )
    end

    intersperse_map(fields, ", ", &[name, ?. | quote_name(&1)])
  end

  defp expr({:not, _, [expr]}, sources, query) do
    ["NOT (", expr(expr, sources, query), ?)]
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map(parts, fn
      {:raw, part} -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
  end

  defp expr({:splice, _, [{:^, m, [idx]}, count]}, sources, query) do
    Enum.map(0..(count - 1), &expr({:^, m, [&1 + idx]}, sources, query))
    |> Enum.intersperse(", ")
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    [expr(arg, sources, query) | " == NULL"]
  end

  defp expr({:in, _, [_left, []]}, _sources, _query) do
    "FALSE"
  end

  defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
    args = intersperse_map(right, ?,, &expr(&1, sources, query))
    [expr(left, sources, query), " IN [", args, ?]]
  end

  defp expr({:in, _, [left, {:^, _, [idx, _length]}]}, sources, query) do
    [expr(left, sources, query), " IN @#{idx + 1}"]
  end

  defp expr({:in, _, [left, right]}, sources, query) do
    [expr(left, sources, query), " IN ", expr(right, sources, query)]
  end

  defp expr({:datetime_add, _, [date, amount, unit]}, sources, query) do
    args = [
      expr(date, sources, query),
      expr(amount, sources, query),
      expr(unit, sources, query)
    ]

    ["DATE_ADD(", Enum.intersperse(args, ", "), ")"]
  end

  defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]

      {:fun, fun} ->
        [fun, ?(, [], intersperse_map(args, ", ", &expr(&1, sources, query)), ?)]
    end
  end

  defp expr(literal, _sources, _query) when is_binary(literal) do
    [?', escape_string(literal), ?']
  end

  defp expr(list, sources, query) when is_list(list) do
    [?[, intersperse_map(list, ?,, &expr(&1, sources, query)), ?]]
  end

  defp expr(%Decimal{} = decimal, _sources, _query) do
    Decimal.to_string(decimal, :normal)
  end

  defp expr(literal, _sources, _query) when is_integer(literal) do
    Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    Float.to_string(literal)
  end

  defp expr(%Ecto.Query.Tagged{value: value, type: :binary_id}, sources, query) do
    [expr(value, sources, query)]
  end

  defp expr(%Ecto.Query.Tagged{value: value, type: :decimal}, sources, query) do
    [expr(value, sources, query)]
  end

  defp expr(%Ecto.Query.Tagged{value: value, type: :integer}, sources, query) do
    ["TO_NUMBER(", expr(value, sources, query), ")"]
  end

  defp expr(%Ecto.Query.Tagged{value: value, type: :string}, sources, query) do
    ["TO_STRING(", expr(value, sources, query), ")"]
  end

  defp expr(%Ecto.Query.Tagged{value: value, type: :boolean}, sources, query) do
    ["TO_BOOL(", expr(value, sources, query), ")"]
  end

  defp expr(nil, _sources, _query), do: "NULL"
  defp expr(true, _sources, _query), do: "TRUE"
  defp expr(false, _sources, _query), do: "FALSE"

  defp name_from_sources(sources, idx) do
    case elem(sources, idx) do
      {:fragment, _, _} ->
        ["frag#{idx}"]

      {_, name, _} ->
        [name]
    end
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
    do: paren_expr(expr, sources, query)

  defp op_to_binary(expr, sources, query), do: expr(expr, sources, query)

  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))

  defp quote_name(name) do
    if String.contains?(name, "`"), do: error!(nil, "bad field name #{inspect(name)}")
    [?`, name, ?`]
  end

  defp quote_collection(name) when is_atom(name), do: quote_collection(Atom.to_string(name))

  defp quote_collection(name) do
    if String.contains?(name, "`"), do: error!(nil, "bad table name #{inspect(name)}")
    [?`, name, ?`]
  end

  defp intersperse_map(list, separator, mapper, acc \\ [])
  defp intersperse_map([], _separator, _mapper, acc), do: acc
  defp intersperse_map([elem], _separator, mapper, acc), do: [acc | mapper.(elem)]

  defp intersperse_map([elem | rest], separator, mapper, acc),
    do: intersperse_map(rest, separator, mapper, [acc, mapper.(elem), separator])

  defp escape_string(value) when is_binary(value) do
    value
    |> :binary.replace("\\", "\\\\", [:global])
    |> :binary.replace("''", "\\'", [:global])
  end

  defp error!(nil, message) do
    raise ArgumentError, message
  end

  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end
end
