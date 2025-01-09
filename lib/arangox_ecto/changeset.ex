defmodule ArangoXEcto.Changeset do
  @moduledoc """
  Methods to manipulate an Ecto Changeset

  The methods within the module are specific to ArangoXEcto and only exist here if there isn't an 
  adequite function available already in the `Ecto.Changeset` module.

  When working with changesets you need to cast or put assocs, well you need to do that for graph
  relations to. However, you need to use a special version of the function called
  `ArangoXEcto.Changeset.cast_graph/3`. This works like the following.

      defmodule MyApp.User do
        import Ecto.Changeset
        import ArangoXEcto.Changeset

        ...

        def changeset(user, attrs \\ %{}) do
          user
          |> cast(attrs, [...])
          |> cast_graph(:my_content, with: %{
            Post => [:title],
            Comment => [:text]
          })
        end
      end

  You can also use the put version (`ArangoXEcto.Changeset.put_graph/4`) just like you would use
  `put_assoc/4`.

  ## cast_graph vs cast_assoc

  `cast_graph` and `cast_assoc` (also the put versions) are very similar in functionality but with 
  some key differences. Firstly, the syntax. You would have seen above that `cast_graph/3` allows
  for a module or a mapper. Secondly, `cast_graph/3` allows for the special multiple nodes to edges
  behaviour as seen above.

  > #### Note {: .error}
  >
  > `cast_assoc/3` and `put_assoc/4` will **NOT** work properly because of how the graph relations
  > work. So you will need to make sure to use the `cast_graph/3` and `put_graph/4` functions.
  """
  @moduledoc since: "2.0.0"

  require Logger

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  @doc """
  Casts the given graph association with the changeset parameters.

  This operates simarly to `Ecto.Changeset.cast_assoc/3` (and indeed was based
  on the implementation) but allows for a relation to represent multiple 
  possible options. For example, in the following `:my_content` can represent 
  either a post or a comment.

      # Implicit use the module changesets
      ArangoXEcto.Changeset.cast_graph(changeset, :my_content)

      # Explicit use the module changesets
      ArangoXEcto.Changeset.cast_graph(changeset, :my_content, with: %{
        Post => &Post.changeset/2,
        Comment => &Comment.changeset/2,
      })

  Like with `Ecto.Changeset.cast_assoc/3`, the changeset must have explicitly preloaded the graph
  association before being cast. Refer to the Ecto docs for more info.

  ## Parameters

    * `changeset` - The Ecto changeset to cast
    * `name` - The name of the field to cast
    * `opts` - Options to use (described below)

  ## Options

    * `:required` - if the graph association is a required field. A non-empty list is 
      satisfactory.

    * `:required_message` - the message on failure, defaults to "can't be blank"

    * `:invalid_message` - the message on failure, defaults to "is invalid"

    * `:force_update_on_change` - force the parent record to be updated in the
      repository if there is a change, defaults to `true`

    * `:with` - can either be a function or a map where the keys are a schema module and the values
      is the function to use. The function is used to build the changeset from params. Defaults to
      the `changeset/2` function of the associated module. It can be an anonymous function that 
      expects two arguments: the associated struct to be cast and its parameters. It must return a
      changeset. Functions with arity 3 are accepted, and the third argument will be the position
      of the associated element in the list, or `nil`, if the association is being replaced.

    * `:drop_param` - the parameter name which keeps a list of indexes to drop from the relation
      parameters

    * `:sort_param` - the parameter name which keeps a list of indexes to sort from the relation
      parameters. Unknown indexes are considered to be new entries. Non-listed indexes will come 
      before any sorted ones.

  """
  @spec cast_graph(Ecto.Changeset.t(), atom(), Keyword.t()) :: Ecto.Changeset.t()
  def cast_graph(changeset, name, opts \\ [])

  def cast_graph(%Changeset{data: %{} = data}, _name, _opts)
      when not is_map_key(data, :__meta__) do
    raise ArgumentError,
          "cast_graph/3 cannot be used to cast associations into embedded schemas or " <>
            "schemaless changesets. Please modify the association independently."
  end

  def cast_graph(%Changeset{data: data, types: types}, _name, _opts)
      when is_nil(data) or is_nil(types) do
    raise ArgumentError,
          "cast_graph/3 expects the changeset to be cast. Please call cast/4 before calling cast_graph/3."
  end

  def cast_graph(%Changeset{} = changeset, name, opts) when is_atom(name) do
    %{data: data, types: types, params: params, changes: changes} = changeset
    {key, param_key} = cast_key(name)
    %{queryables: queryables} = relation = relation!(:cast, key, Map.get(types, key))
    params = params || %{}

    {changeset, required?} =
      if opts[:required] do
        {update_in(changeset.required, &[key | &1]), true}
      else
        {changeset, false}
      end

    on_cast =
      Keyword.get_lazy(opts, :with, fn -> on_cast_default(queryables) end)

    validate_on_cast!(on_cast, queryables)

    sort = opts_key_from_params(:sort_param, opts, params)
    drop = opts_key_from_params(:drop_param, opts, params)

    changeset =
      if is_map_key(params, param_key) or is_list(sort) or is_list(drop) do
        value = Map.get(params, param_key)
        original = Map.get(data, key)
        current = Relation.load!(data, original)
        value = cast_params(value, sort, drop)

        do_cast_graph(
          changeset,
          relation,
          changes,
          {key, value},
          {original, current},
          required?,
          on_cast,
          opts
        )
      else
        missing_relation(changeset, key, Map.get(data, key), required?, relation, opts)
      end

    update_in(changeset.types[key], fn {type, relation} ->
      {type, %{relation | on_cast: on_cast}}
    end)
  end

  defp do_cast_graph(
         changeset,
         relation,
         changes,
         {key, value},
         {original, current},
         required?,
         on_cast,
         opts
       ) do
    case cast(relation, value, current, on_cast) do
      {:ok, change, relation_valid?} when change != original ->
        valid? = changeset.valid? and relation_valid?
        changes = Map.put(changes, key, change)
        changeset = %{force_update(changeset, opts) | changes: changes, valid?: valid?}
        missing_relation(changeset, key, current, required?, relation, opts)

      {:error, {message, meta}} ->
        meta = [validation: :assoc] ++ meta
        error = {key, {Keyword.get(opts, :invalid_message, message), meta}}
        %{changeset | errors: [error | changeset.errors], valid?: false}

      # ignore or ok with changes == orginal
      _ ->
        missing_relation(changeset, key, current, required?, relation, opts)
    end
  end

  defp cast(relation, params, current, on_cast) do
    fun = &do_cast(relation, &1, &2, &3, &4, on_cast)

    with :error <- cast_or_change(relation, params, current, fun) do
      {:error, {"is invalid", [type: {:array, :map}]}}
    end
  end

  defp do_cast(relation, params, nil, allowed_actions, idx, on_cast) do
    mod = identified_by_fields(relation, params)

    {:ok,
     get_cast(on_cast, mod, relation)
     |> apply_on_cast(struct(mod), params, idx)
     |> put_new_action(:insert)
     |> check_action!(allowed_actions)}
  end

  defp do_cast(relation, nil, struct, _allowed_actions, _idx, _on_cast) do
    on_replace(relation, struct)
  end

  # this may never be called... maybe remove??
  defp do_cast(relation, params, struct, allowed_actions, idx, on_cast) do
    mod = identified_by_fields(relation, params)

    {:ok,
     get_cast(on_cast, mod, relation)
     |> apply_on_cast(struct, params, idx)
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp get_cast(on_cast, _mod, _relation) when is_function(on_cast), do: on_cast
  defp get_cast(on_cast, mod, _relation) when is_map(on_cast), do: Map.get(on_cast, mod)

  defp get_cast(_, mod, relation),
    do:
      raise(
        ArgumentError,
        "with for relation #{relation.field} must specify a changeset function for #{mod}"
      )

  defp identified_by_fields(%{mapping: mod}, _params) when is_atom(mod), do: mod

  defp identified_by_fields(%{mapping: mapper}, params) when is_map(mapper) do
    param_keys = Map.keys(params) |> Enum.map(&to_string/1) |> MapSet.new()

    Enum.find_value(mapper, fn {mod, fields} ->
      map_set_fields = Enum.map(fields, &to_string/1) |> MapSet.new()

      if MapSet.subset?(map_set_fields, param_keys) do
        mod
      end
    end)
  end

  defp identified_by_fields(%{queryables: queryables, field: field, owner: owner}, _params) do
    raise ArgumentError,
          "relation #{field} in #{owner} must have a map as the associated target " <>
            "fields, got: #{inspect(queryables)}"
  end

  defp apply_on_cast(on_cast, struct, params, idx) when is_function(on_cast, 3),
    do: on_cast.(struct, params, idx)

  defp apply_on_cast(on_cast, struct, params, _idx) when is_function(on_cast, 2),
    do: on_cast.(struct, params)

  defp put_new_action(%{action: action} = changeset, new_action) when is_nil(action),
    do: Map.put(changeset, :action, new_action)

  defp put_new_action(changeset, _new_action),
    do: changeset

  defp check_action!(changeset, allowed_actions) do
    action = changeset.action

    cond do
      action in allowed_actions ->
        changeset

      action == :ignore ->
        changeset

      action == :insert ->
        raise RuntimeError,
              "cannot insert related #{inspect(changeset.data)} " <>
                "because it is already associated with the given struct"

      action == :replace ->
        raise RuntimeError,
              "cannot replace related #{inspect(changeset.data)}. " <>
                "This typically happens when you are calling put_graph " <>
                "with the results of a previous put_graph operation, which" <>
                "is not supported. You must call such operations only once " <>
                "per graph relation, in order for Ecto to track changes efficiently."

      true ->
        raise RuntimeError,
              "cannot #{action} related #{inspect(changeset.data)} because " <>
                "it already exists and is not currrently associated with the " <>
                "given struct. Ecto forbids casting existing records through " <>
                "the association field for security reasons."
    end
  end

  defp cast_or_change(relation, value, current, fun) when is_list(value) do
    current_map = process_current(current, relation)

    map_changes(value, fun, current_map, [], true, true, 0)
  end

  defp process_current(nil, _relation), do: {[], %{}}

  defp process_current(current, relation) do
    {map, counter} =
      Enum.reduce(current, {%{}, 0}, fn struct, {acc, counter} ->
        id_val = id_from_data(struct)
        {Map.put(acc, id_val, struct), counter + 1}
      end)

    if map_size(map) != counter do
      Logger.warning("""
      found duplicate primary keys for graph relation `#{inspect(relation.field)}` \
      in `#{inspect(relation.owner)}`. In case of duplicate IDs, only the last entry \
      with the same ID will be kept. Make sure that all entries in `#{inspect(relation.field)}` \
      have an ID and the IDs are unique between them.
      """)
    end

    map
  end

  defp id_from_data(%Changeset{data: data}), do: Map.get(data, :id)
  defp id_from_data(map) when is_map(map), do: Map.get(map, :id)
  defp id_from_data(list) when is_list(list), do: Keyword.get(list, :id)

  defp id_from_params(params) do
    original = Map.get(params, "id") || Map.get(params, :id)

    case Ecto.Type.cast(:binary_id, original) do
      {:ok, value} -> value
      _ -> original
    end
  end

  defp map_changes([], fun, current, acc, valid?, skip?, _idx) do
    current_structs = Enum.map(current, &elem(&1, 1))
    reduce_delete_changesets(current_structs, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes([changes | rest], fun, current, acc, valid?, skip?, idx)
       when is_map(changes) or is_list(changes) do
    id_value = id_from_params(changes)
    {struct, current, allowed_actions} = pop_current(current, id_value)

    case fun.(changes, struct, allowed_actions, idx) do
      {:ok, %{action: :ignore}} ->
        map_changes(rest, fun, current, acc, valid?, skip?, idx + 1)

      {:ok, changeset} ->
        valid? = valid? and changeset.valid?
        skip? = not is_nil(struct) and skip? and skip?(changeset)
        map_changes(rest, fun, current, [changeset | acc], valid?, skip?, idx + 1)

      :error ->
        :error
    end
  end

  defp map_changes(_params, _fun, _current, _acc, _valid?, _skip?, _idx), do: :error

  defp reduce_delete_changesets([], _fun, _acc, _valid?, true), do: :ignore
  defp reduce_delete_changesets([], _fun, acc, valid?, false), do: {:ok, acc, valid?}

  defp reduce_delete_changesets([struct | rest], fun, acc, valid?, _skip?) do
    with {:ok, changeset} <- fun.(nil, struct, [:update, :delete], nil) do
      valid? = valid? and changeset.valid?
      reduce_delete_changesets(rest, fun, [changeset | acc], valid?, false)
    end
  end

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{}, do: true
  defp skip?(_changeset), do: false

  defp pop_current(current, id_value) do
    case Map.pop(current, id_value) do
      {nil, current} -> {nil, current, [:insert]}
      {struct, current} -> {struct, current, allowed_actions(id_value)}
    end
  end

  defp allowed_actions(nil), do: [:insert, :update, :delete]
  defp allowed_actions(_), do: [:update, :delete]

  defp cast_params(nil, sort, drop) when is_list(sort) or is_list(drop) do
    cast_params(%{}, sort, drop)
  end

  defp cast_params(value, sort, drop) when is_map(value) do
    drop = if is_list(drop), do: drop, else: []

    {sorted, pending} =
      if is_list(sort) do
        Enum.map_reduce(sort -- drop, value, &Map.pop(&2, &1, %{}))
      else
        {[], value}
      end

    sorted ++
      (pending
       |> Map.drop(drop)
       |> Stream.map(&key_as_int/1)
       |> Enum.sort()
       |> Enum.map(&elem(&1, 1)))
  end

  defp cast_params(value, _sort, _drop), do: value

  defp key_as_int({key, val}) when is_binary(key) and byte_size(key) < 32 do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end

  defp key_as_int(key_val), do: key_val

  defp cast_key(key) when is_atom(key), do: {key, Atom.to_string(key)}

  defp missing_relation(
         %{changes: changes, errors: errors} = changeset,
         name,
         current,
         required?,
         relation,
         opts
       ) do
    current_changes = Map.get(changes, name, current)

    if required? and Relation.empty?(relation, current_changes) do
      errors = [
        {name, Keyword.get(opts, :required_messages, "can't be blank"), [validation: :required]}
        | errors
      ]

      %{changeset | errors: errors, valid?: false}
    else
      changeset
    end
  end

  defp relation!(_op, _name, {:assoc, relation}), do: relation

  defp relation!(op, name, _) do
    raise ArgumentError,
          "cannot #{op} assoc `#{name}`, assoc `#{name}` not found. " <>
            "Make sure it is spelled correctly and that the association type is not read-only."
  end

  defp force_update(changeset, opts) do
    if Keyword.get(opts, :force_update_on_change, true) do
      put_in(changeset.repo_opts[:force], true)
    else
      changeset
    end
  end

  defp on_cast_default(related) do
    for mod <- related do
      fun = fn struct, params ->
        try do
          mod.changeset(struct, params)
        rescue
          e in UndefinedFunctionError ->
            case __STACKTRACE__ do
              [{^mod, :changeset, args_or_arity, _} | _]
              when args_or_arity == 2 or length(args_or_arity) == 2 ->
                reraise ArgumentError,
                        [
                          message: """
                          the module #{inspect(mod)} does not define a changeset/2 function,
                          which is used by cast_graph/3. You need to either:
                            
                            1. implement the changeset/2 function
                            2. pass the :with option to cast_graph/3 with an anonymous function of arity 2
                          """
                        ],
                        __STACKTRACE__

              stacktrace ->
                reraise e, stacktrace
            end
        end
      end

      {mod, fun}
    end
    |> Map.new()
  end

  defp validate_on_cast!(on_cast, _related) when is_function(on_cast, 2), do: :ok

  defp validate_on_cast!(on_cast, related) when is_map(on_cast) do
    Enum.each(on_cast, fn
      {module, fun} when not is_function(fun, 2) ->
        raise ArgumentError,
              "the function for module #{inspect(module)} is not a valid function. " <>
                "Expects a function with arity 2, the first argument being the struct and " <>
                "the second being the attributes."

      {module, _fun} ->
        if module not in related do
          raise ArgumentError,
                "the module #{inspect(module)} is not a valid related schema for this association."
        end

      _ ->
        :ok
    end)
  end

  defp validate_on_cast!(on_cast, _realted) do
    raise ArgumentError, "the with clause is not valid, got: #{inspect(on_cast)}"
  end

  defp opts_key_from_params(opt, opts, params) do
    if key = opts[opt] do
      Map.get(params, Atom.to_string(key))
    end
  end

  @doc """
  Puts the given graph association entry or entries into a graph association.

  This operates simarly to `Ecto.Changeset.put_assoc/4` (and indeed was based
  off of the implementation) but allows for a relation to represent multiple 
  possible options. For example, in the following `:my_content` can represent 
  either a post or a comment.

      ArangoXEcto.Changeset.put_graph(changeset, :my_content, [
        %Post{title: "abc"},
        %Comment{text: "cba"}
      ])

  This operates on the graph association as a whole. So for example the above will replace the
  `:my_content` edges between the nodes. This works exactly the same as
  `Ecto.Changeset.put_assoc/4`. Therefore, if you want to update the content you will have to
  preload the value and update from there. The `:on_replace` value for the field applies here.

  An empty list can be given too.

  The data provided is the same as the available options in `Ecto.Changeset.put_assoc/4`. I.e. you
  can provide a map, a keyword list, a changeset or a struct as the options in the list.

  Although it accepts an `opts` argument, there are no options currently supported by 
  `put_graph/4`.

  ## Parameters

    * `changeset` - The Ecto changeset to apply the change to
    * `name` - The name of the field to put the value to
    * `value` - The value of the field to apply
    * `opts` - none available currently
  """
  @spec put_graph(Ecto.Changeset.t(), atom(), term(), Keyword.t()) :: Ecto.Changeset.t()
  def put_graph(changeset, name, value, opts \\ [])

  def put_graph(%{types: nil}, _name, _value, _opts) do
    raise ArgumentError, "changeset does not have types information"
  end

  def put_graph(
        %Changeset{} = changeset,
        name,
        value,
        _opts
      ) do
    %{data: data, types: types, changes: changes, errors: errors, valid?: valid?} = changeset
    relation = relation!(:put, name, Map.get(types, name))

    {changes, errors, valid?} =
      put_change(data, changes, errors, valid?, name, value, {:assoc, relation})

    %{changeset | changes: changes, errors: errors, valid?: valid?}
  end

  defp put_change(data, changes, errors, valid?, key, value, {:assoc, relation}) do
    original = Map.get(data, key)
    current = Relation.load!(data, original)

    case change(relation, value, current) do
      {:ok, change, relation_valid?} when change != original ->
        {Map.put(changes, key, change), errors, valid? and relation_valid?}

      {:error, error} ->
        {changes, [{key, error} | errors], false}

      # ignore or ok with change == original
      _ ->
        {Map.delete(changes, key), errors, valid?}
    end
  end

  defp change(%{related: mod} = relation, value, current) do
    get_pks = data_pk(mod.__schema__(:primary_key))

    with :error <-
           cast_or_change(
             relation,
             value,
             current,
             get_pks,
             get_pks,
             &do_change(relation, &1, &2, &3, &4)
           ) do
      {:error, {"is invalid", [type: {:array, :map}]}}
    end
  end

  defp data_pk(pks) do
    fn
      %Changeset{data: data} -> Enum.map(pks, &Map.get(data, &1))
      map when is_map(map) -> Enum.map(pks, &Map.get(map, &1))
      list when is_list(list) -> Enum.map(pks, &Keyword.get(list, &1))
    end
  end

  defp do_change(relation, %{__struct__: _} = changeset_or_struct, nil, _allowed_actions, _idx) do
    changeset = Ecto.Changeset.change(changeset_or_struct)

    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(action_from_changeset(changeset, nil))}
  end

  defp do_change(relation, nil, current, _allowed_actions, _idx) do
    on_replace(relation, current)
  end

  defp do_change(relation, %Changeset{} = changeset, _current, allowed_actions, _idx) do
    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp do_change(_relation, %{__struct__: _} = struct, _current, allowed_actions, _idx) do
    {:ok,
     struct
     |> Ecto.Changeset.change()
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp do_change(relation, changes, current, allowed_actions, idx)
       when is_list(changes) or is_map(changes) do
    changeset =
      Ecto.Changeset.change(current || relation.__struct__.build(relation, nil), changes)

    changeset = put_new_action(changeset, action_from_changeset(changeset, current))
    do_change(relation, changeset, current, allowed_actions, idx)
  end

  defp on_replace(%{on_replace: :mark_as_invalid}, _changeset_or_struct) do
    :error
  end

  defp on_replace(%{on_replace: :raise, field: name, owner: owner}, _) do
    raise """
    you are attempting to change graph relation #{inspect(name)} of
    #{inspect(owner)} but the `:on_replace` option of this relation
    is set to `:raise`.

    By default it is not possible to replace or delete embeds and
    associations during `cast`. Therefore Ecto requires the parameters
    given to `cast` to have IDs matching the data currently associated
    to #{inspect(owner)}. Failing to do so results in this error message.

    If you want to replace data or automatically delete any data
    not sent to `cast`, please set the appropriate `:on_replace`
    option when defining the relation. The docs for `Ecto.Changeset`
    covers the supported options in the "Associations, embeds and on
    replace" section.

    However, if you don't want to allow data to be replaced or
    deleted, only updated, make sure that:

      * If you are attempting to update an existing entry, you
        are including the entry primary key (ID) in the data.

      * If you have a relationship with many children, all children
        must be given on update.

    """
  end

  defp on_replace(_relation, changeset_or_struct) do
    {:ok, Ecto.Changeset.change(changeset_or_struct) |> put_new_action(:replace)}
  end

  defp action_from_changeset(%{data: %{__meta__: %{state: state}}}, _current) do
    case state do
      :built -> :insert
      :loaded -> :update
      :deleted -> :delete
    end
  end

  defp action_from_changeset(_, nil) do
    :insert
  end

  defp action_from_changeset(_, _current) do
    :update
  end

  defp assert_changeset_struct!(%{data: %{__struct__: mod} = data} = changeset, %{
         queryables: mods
       }) do
    if mod in mods do
      changeset
    else
      raise ArgumentError, "expected changeset data to be a #{mod} struct, got: #{inspect(data)}"
    end
  end

  defp cast_or_change(_relation, [], [], _current_pks, _new_pks, _fun) do
    {:ok, [], true}
  end

  defp cast_or_change(relation, value, current, current_pks_fun, new_pks_fun, fun)
       when is_list(value) do
    {current_pks, current_map} = process_current(current, current_pks_fun, relation)
    %{unique: unique, ordered: ordered, related: mod} = relation
    change_pks_fun = change_pk(mod.__schema__(:primary_key))
    ordered = if ordered, do: current_pks, else: []

    map_changes(
      value,
      {new_pks_fun, change_pks_fun},
      fun,
      current_map,
      [],
      {true, true},
      0,
      {unique && %{}, ordered}
    )
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  defp process_current(nil, _get_pks, _relation),
    do: {[], %{}}

  defp process_current(current, get_pks, relation) do
    {pks, {map, counter}} =
      Enum.map_reduce(current, {%{}, 0}, fn struct, {acc, counter} ->
        pks = get_pks.(struct)
        key = if pks == [], do: map_size(acc), else: pks
        {pks, {Map.put(acc, key, struct), counter + 1}}
      end)

    if map_size(map) != counter do
      Logger.warning("""
      found duplicate primary keys for graph association `#{inspect(relation.field)}` \
      in `#{inspect(relation.owner)}`. In case of duplicate IDs, only the last entry \
      with the same ID will be kept. Make sure that all entries in `#{inspect(relation.field)}` \
      have an ID and the IDs are unique between them
      """)
    end

    {pks, map}
  end

  defp change_pk(pks) do
    fn %Changeset{} = cs ->
      Enum.map(pks, &get_change_pk(cs, &1))
    end
  end

  defp get_change_pk(cs, pk) do
    case cs.changes do
      %{^pk => pk_value} -> pk_value
      _ -> Map.get(cs.data, pk)
    end
  end

  defp map_changes(
         [changes | rest],
         {new_pks, change_pks},
         fun,
         current,
         acc,
         {valid?, skip?},
         idx,
         {unique, ordered}
       )
       when is_map(changes) or is_list(changes) do
    pk_values = new_pks.(changes)
    {struct, current, allowed_actions} = pop_current(current, pk_values)

    case fun.(changes, struct, allowed_actions, idx) do
      {:ok, %{action: :ignore}} ->
        ordered = pop_ordered(pk_values, ordered)

        map_changes(
          rest,
          {new_pks, change_pks},
          fun,
          current,
          acc,
          {valid?, skip?},
          idx + 1,
          {unique, ordered}
        )

      {:ok, changeset} ->
        pk_values = change_pks.(changeset)
        changeset = maybe_add_error_on_pk(changeset, pk_values, unique)
        acc = [changeset | acc]
        valid? = valid? and changeset.valid?
        skip? = struct != nil and skip? and skip?(changeset)
        unique = unique && Map.put(unique, pk_values, true)
        ordered = pop_ordered(pk_values, ordered)

        map_changes(
          rest,
          {new_pks, change_pks},
          fun,
          current,
          acc,
          {valid?, skip?},
          idx + 1,
          {unique, ordered}
        )

      :error ->
        :error
    end
  end

  defp map_changes(
         [],
         _pks_funcs,
         fun,
         current,
         acc,
         {valid?, skip?},
         _idx,
         {_unique, ordered}
       ) do
    current_structs = Enum.map(current, &elem(&1, 1))
    skip? = skip? and ordered == []
    reduce_delete_changesets(current_structs, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes(
         _params,
         _pks_funcs,
         _fun,
         _current,
         _acc,
         _valid_skips?,
         _idx,
         _unique_ordered
       ) do
    :error
  end

  defp pop_ordered(pk_values, [pk_values | tail]), do: tail
  defp pop_ordered(_pk_values, tail), do: tail

  defp maybe_add_error_on_pk(%{data: %{__struct__: schema}} = changeset, pk_values, unique) do
    if is_map(unique) and not missing_pks?(pk_values) and Map.has_key?(unique, pk_values) do
      Enum.reduce(schema.__schema__(:primary_key), changeset, fn pk, acc ->
        Ecto.Changeset.add_error(acc, pk, "has already been taken")
      end)
    else
      changeset
    end
  end

  defp missing_pks?(pk_values) do
    pk_values == [] or Enum.any?(pk_values, &is_nil/1)
  end
end
