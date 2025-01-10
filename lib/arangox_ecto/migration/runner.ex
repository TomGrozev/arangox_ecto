defmodule ArangoXEcto.Migration.Runner do
  @moduledoc false
  use Agent, restart: :temporary

  require Logger

  alias ArangoXEcto.Migration.{Analyzer, Collection, Command, Index, View}

  @doc """
  Runs the given migration.
  """
  @spec run(
          Ecto.Repo.t(),
          Keyword.t(),
          integer(),
          module(),
          :forward | :backward,
          :up | :down | :change,
          :up | :down,
          Keyword.t()
        ) :: :ok
  def run(repo, config, version, module, direction, operation, migrator_direction, opts) do
    level = Keyword.get(opts, :log, :info)
    log_migrations = Keyword.get(opts, :log_migrations, :info)
    log = %{level: level, log_migrations: log_migrations}
    args = {self(), repo, config, module, direction, migrator_direction, log}

    {:ok, runner} =
      DynamicSupervisor.start_child(ArangoXEcto.MigratorSupervisor, {__MODULE__, args})

    metadata(runner, opts)

    log(level, "== Running #{version} #{inspect(module)}.#{operation}/0 #{direction}")
    {time, _} = :timer.tc(fn -> perform_operation(repo, module, operation) end)
    log(level, "== Migrated #{version} in #{inspect(div(time, 100_000) / 10)}s")
  after
    stop()
  end

  @doc """
  Stores the metadata of the runner
  """
  @spec metadata(pid(), Keyword.t()) :: map() | nil
  def metadata(runner, opts) do
    prefix = opts[:prefix]
    Process.put(:ecto_migration, %{runner: runner, prefix: prefix && to_string(prefix)})
  end

  @doc """
  Starts the runner for the repo passed.
  """
  def start_link({parent, repo, config, module, direction, migrator_direction, log}) do
    Agent.start_link(fn ->
      Process.link(parent)

      %{
        direction: direction,
        repo: repo,
        migration: module,
        migrator_direction: migrator_direction,
        command: nil,
        subcommand: nil,
        subcommands: [],
        log: log,
        commands: [],
        config: config
      }
    end)
  end

  @doc """
  Stops the runner
  """
  def stop do
    Agent.stop(runner())
  end

  @doc """
  Starts a command.
  """
  def start_command(command) do
    Agent.get_and_update(runner(), fn
      %{command: nil} = state ->
        {:ok, %{state | command: command}}

      %{command: _} = state ->
        {:error, %{state | command: command}}
    end)
    |> case do
      :ok -> :ok
      :error -> raise Ecto.MigrationError, "cannot execute nested commands"
    end
  end

  @doc """
  Queues and clears the current command.

  Must call `start_command/1` first.
  """
  def end_command do
    Agent.update(runner(), fn state ->
      {operation, object} = state.command
      command = {operation, object, Enum.reverse(state.subcommands)}

      %{state | command: nil, subcommands: [], commands: [command | state.commands]}
    end)
  end

  @doc """
  Adds a subcommand to the current command.

  `start_command/1` must be called first.
  """
  def subcommand(subcommand) do
    Agent.get_and_update(runner(), fn
      %{command: nil} = state ->
        {{:error, "cannot execute command outside of block"}, state}

      %{command: command, subcommands: [{embed_opt, name, subcommands, opts} | t]} = state
      when embed_opt in [:add_embed, :modify_embed, :add_embed_many, :modify_embed_many] ->
        validate_type(command, subcommand, state, fn ->
          put_in(state.subcommands, [{embed_opt, name, [subcommand | subcommands], opts} | t])
        end)

      %{command: command} = state ->
        validate_type(command, subcommand, state, fn ->
          update_in(state.subcommands, &[subcommand | &1])
        end)
    end)
    |> case do
      :ok ->
        :ok

      {:error, msg} ->
        raise Ecto.MigrationError, message: msg
    end
  end

  @doc """
  Queues and clears the current subcommand.

  Must call `subcommand/1` first.
  """
  def end_subcommand do
    Agent.update(runner(), fn
      %{subcommands: [{:add_embed, name, subcommands, opts} | t]} = state ->
        command = {:add, name, Enum.reverse(subcommands), opts}

        %{state | subcommands: [command | t]}

      %{subcommands: [{:modify_embed, name, subcommands, opts} | t]} = state ->
        command = {:modify, name, Enum.reverse(subcommands), opts}

        %{state | subcommands: [command | t]}

      %{subcommands: [{:add_embed_many, name, subcommands, opts} | t]} = state ->
        command = {:add, name, {:array, Enum.reverse(subcommands)}, opts}

        %{state | subcommands: [command | t]}

      %{subcommands: [{:modify_embed_many, name, subcommands, opts} | t]} = state ->
        command = {:modify, name, {:array, Enum.reverse(subcommands)}, opts}

        %{state | subcommands: [command | t]}
    end)
  end

  @doc """
  Gets the prefix for the migration module
  """
  def prefix do
    case Process.get(:ecto_migration) do
      %{prefix: prefix} -> prefix
      _ -> raise "could not find migration runner process for #{inspect(self())}"
    end
  end

  @doc """
  Accesses the repo configuration
  """
  def repo_config(key, default) do
    Agent.get(runner(), &Keyword.get(&1.config, key, default))
  end

  @doc """
  Returns the migrator command (up or down).

    * forward + up: up
    * forward + down: down
    * forward + change: up
    * backward + change: down

  """
  def migrator_direction do
    Agent.get(runner(), & &1.migrator_direction)
  end

  @doc """
  Gets the repo for this migration
  """
  def repo do
    Agent.get(runner(), & &1.repo)
  end

  @doc """
  Executes queued migration commands.

  Reverses the order of commands when doing a change/0 rollback,
  then resets the command queue.
  """
  def flush do
    %{commands: commands, direction: direction, repo: repo, log: log, migration: module} =
      Agent.get_and_update(runner(), fn state -> {state, %{state | commands: []}} end)

    commands = if direction == :backward, do: commands, else: Enum.reverse(commands)

    for command <- commands do
      execute_in_direction(repo, module, direction, log, command)
    end
  end

  @doc """
  Queues a command tuple for execution

  `Ecto.MigrationError` will be raised when the server
  is in `:backward` direction and `command` is irreversible.
  """
  def execute(command) do
    Agent.get_and_update(runner(), fn
      %{command: nil} = state ->
        {:ok, %{state | subcommands: [], commands: [command | state.commands]}}

      %{command: _} = state ->
        {:error, %{state | command: nil}}
    end)
    |> case do
      :ok ->
        :ok

      :error ->
        raise Ecto.MigrationError, "cannot execute nested commands"
    end
  end

  ###########
  # Execute #
  ###########

  @allowed_view_commands [
    :add_sort,
    :add_store,
    :add_link,
    :remove_link
  ]
  @allowed_collection_commands [
    :add,
    :add_if_not_exists,
    :modify,
    :remove,
    :remove_if_exists,
    :rename,
    :add_embed,
    :modify_embed,
    :add_embed_many,
    :modify_embed_many
  ]
  defp validate_type(command, subcommand, state, fun) do
    elems = {elem(command, 0), elem(command, 1).__struct__}

    subcommand = elem(subcommand, 0)

    case elems do
      {:alter, View}
      when subcommand in [
             :add_link,
             :remove_link
           ] ->
        {:ok, fun.()}

      {_, View}
      when subcommand in @allowed_view_commands ->
        {:ok, fun.()}

      {_, Collection}
      when subcommand in @allowed_collection_commands ->
        {:ok, fun.()}

      _ ->
        {{:error, "invalid subcommand type `#{subcommand}` for command `#{inspect(command)}`"},
         state}
    end
  end

  defp execute_in_direction(repo, module, :forward, log, %Command{up: up}),
    do: log_and_execute_command(repo, module, log, up)

  defp execute_in_direction(repo, module, :forward, log, command),
    do: log_and_execute_command(repo, module, log, command)

  defp execute_in_direction(repo, module, :backward, log, %Command{down: down}),
    do: log_and_execute_command(repo, module, log, down)

  defp execute_in_direction(repo, module, :backward, log, command) do
    if reversed = reverse(command) do
      log_and_execute_command(repo, module, log, reversed)
    else
      raise Ecto.MigrationError,
        message:
          "cannot reverse migration command: #{command(command)}. " <>
            "You will need to explicitly define up/0 and down/0 in your migration"
    end
  end

  # Collection
  defp reverse({:create, %Collection{} = collection, _columns}),
    do: {:drop, collection}

  defp reverse({:create_if_not_exists, %Collection{} = collection, _columns}),
    do: {:drop_if_exists, collection}

  defp reverse({:rename, %Collection{} = collection_current, %Collection{} = collection_new}),
    do: {:rename, collection_new, collection_current}

  defp reverse({:alter, %Collection{} = collection, changes}) do
    if reversed = collection_reverse(changes, []) do
      {:alter, collection, reversed}
    end
  end

  # Index
  defp reverse({:create, %Index{} = index}),
    do: {:drop, index}

  defp reverse({:create_if_not_exists, %Index{} = index}),
    do: {:drop_if_exists, index}

  defp reverse({:drop, %Index{} = index}),
    do: {:create, index}

  defp reverse({:drop_if_exists, %Index{} = index}),
    do: {:create_if_not_exists, index}

  # Analyzer
  defp reverse({:create, %Analyzer{} = analyzer}),
    do: {:drop, analyzer}

  defp reverse({:create_if_not_exists, %Analyzer{} = analyzer}),
    do: {:drop_if_exists, analyzer}

  # View
  defp reverse({:create, %View{} = view, _}),
    do: {:drop, view}

  defp reverse({:create_if_not_exists, %View{} = view, _}),
    do: {:drop_if_exists, view}

  defp reverse({:rename, %View{} = view_current, %View{} = view_new}),
    do: {:rename, view_new, view_current}

  defp reverse({:alter, %View{} = view, changes}) do
    if reversed = view_reverse(changes, []) do
      {:alter, view, reversed}
    end
  end

  defp reverse(_command), do: false

  defp collection_reverse([{:remove, name, type, opts} | t], acc) do
    collection_reverse(t, [{:add, name, type, opts} | acc])
  end

  defp collection_reverse([{type, name, subcommands, opts} | t], acc)
       when is_list(subcommands) and type in [:add, :modify] do
    collection_reverse(t, [{type, name, collection_reverse(subcommands, []), opts} | acc])
  end

  defp collection_reverse([{:modify, name, type, opts} | t], acc) do
    case opts[:from] do
      nil ->
        false

      {reverse_type, from_opts} when is_list(from_opts) ->
        reverse_from = {type, Keyword.delete(opts, :from)}
        reverse_opts = Keyword.put(from_opts, :from, reverse_from)
        collection_reverse(t, [{:modify, name, reverse_type, reverse_opts} | acc])

      reverse_type ->
        reverse_opts = Keyword.put(opts, :from, type)
        collection_reverse(t, [{:modify, name, reverse_type, reverse_opts} | acc])
    end
  end

  defp collection_reverse([{:rename, current_field, new_field} | t], acc) do
    collection_reverse(t, [{:rename, new_field, current_field} | acc])
  end

  defp collection_reverse([{:add, name, type, _opts} | t], acc) do
    collection_reverse(t, [{:remove, name, type, []} | acc])
  end

  defp collection_reverse([_ | _], _acc), do: false

  defp collection_reverse([], acc), do: acc

  defp view_reverse([{:remove_link, schema_name, link} | t], acc) do
    view_reverse(t, [{:add_link, schema_name, link} | acc])
  end

  defp view_reverse([{:remove_sort, field, direction} | t], acc) do
    view_reverse(t, [{:add_sort, field, direction} | acc])
  end

  defp view_reverse([{:remove_store, fields, compression} | t], acc) do
    view_reverse(t, [{:add_sort, fields, compression} | acc])
  end

  defp view_reverse([{:modify_sort, field, direction, [from: from_direction]} | t], acc) do
    view_reverse(t, [{:modify_sort, field, from_direction, [from: direction]} | acc])
  end

  defp view_reverse([{:modify_store, fields, compression, [from: from_compression]} | t], acc) do
    view_reverse(t, [{:modify_store, fields, from_compression, [from: compression]} | acc])
  end

  defp view_reverse([{:add_link, schema_name, link} | t], acc) do
    view_reverse(t, [{:remove_link, schema_name, link} | acc])
  end

  defp view_reverse([{:add_sort, field, direction} | t], acc) do
    view_reverse(t, [{:remove_sort, field, direction} | acc])
  end

  defp view_reverse([{:add_store, fields, compression} | t], acc) do
    view_reverse(t, [{:remove_store, fields, compression} | acc])
  end

  defp view_reverse([_ | _], _acc), do: false

  defp view_reverse([], acc), do: acc

  ###########
  # Helpers #
  ###########

  defp perform_operation(repo, module, operation) do
    if function_exported?(repo, :in_transaction?, 0) and repo.in_transaction?() do
      if function_exported?(module, :after_begin, 0) do
        module.after_begin()
        flush()
      end

      apply(module, operation, [])
      flush()

      if function_exported?(module, :before_commit, 0) do
        module.before_commit()
        flush()
      end
    else
      apply(module, operation, [])
      flush()
    end
  end

  defp log_and_execute_command(repo, _module, log, command) do
    log_and_execute_command(repo, log, command)
  end

  defp log_and_execute_command(_repo, _log, func) when is_function(func, 0) do
    func.()
    :ok
  end

  defp log_and_execute_command(repo, %{level: level, log_migrations: log_migrations}, command) do
    log(level, command(command))

    {:ok, logs} =
      repo.__adapter__().execute_ddl(repo, command,
        log: if(level, do: log_migrations, else: false)
      )

    Enum.each(logs, fn {res_level, message, metadata} ->
      log_result(res_level, level, message, metadata)
    end)

    :ok
  end

  defp runner do
    case Process.get(:ecto_migration) do
      %{runner: runner} -> runner
      _ -> raise "could not find migration runner process for #{inspect(self())}"
    end
  end

  defp log_result(_level, false, _msg, _metadata), do: :ok
  defp log_result(level, _, msg, metadata), do: log(level, msg, metadata)

  defp log(level, msg, metadata \\ [])
  defp log(false, _msg, _metadata), do: :ok
  defp log(true, msg, metadata), do: log(:info, msg, metadata)
  defp log(level, msg, metadata), do: Logger.log(level, msg, metadata)

  defp command(aql) when is_binary(aql) or is_list(aql), do: "execute #{inspect(aql)}"

  # Analyzer
  defp command({:create, %Analyzer{prefix: prefix, name: name}}),
    do: "create analyzer #{quote_name(prefix, name)}"

  defp command({:create_if_not_exists, %Analyzer{prefix: prefix, name: name}}),
    do: "create analyzer if not exists #{quote_name(prefix, name)}"

  defp command({:rename, %Analyzer{} = current_analyzer, %Analyzer{} = new_analyzer}),
    do:
      "rename analyzer #{quote_name(current_analyzer.prefix, current_analyzer.name)} to #{quote_name(new_analyzer.prefix, new_analyzer.name)}"

  defp command({:drop, %Analyzer{prefix: prefix, name: name}}),
    do: "drop analyzer #{quote_name(prefix, name)}"

  defp command({:drop_if_exists, %Analyzer{prefix: prefix, name: name}}),
    do: "drop analyzer if exists #{quote_name(prefix, name)}"

  # View
  defp command({:create, %View{prefix: prefix, name: name}, _}),
    do: "create view #{quote_name(prefix, name)}"

  defp command({:create_if_not_exists, %View{prefix: prefix, name: name}, _}),
    do: "create view if not exists #{quote_name(prefix, name)}"

  defp command({:alter, %View{prefix: prefix, name: name}, _}),
    do: "alter view #{quote_name(prefix, name)}"

  defp command({:rename, %View{} = current_view, %View{} = new_view}),
    do:
      "rename view #{quote_name(current_view.prefix, current_view.name)} to #{quote_name(new_view.prefix, new_view.name)}"

  defp command({:drop, %View{prefix: prefix, name: name}}),
    do: "drop view #{quote_name(prefix, name)}"

  defp command({:drop_if_exists, %View{prefix: prefix, name: name}}),
    do: "drop view if exists #{quote_name(prefix, name)}"

  # Collection
  defp command({:create, %Collection{prefix: prefix, name: name}, _}),
    do: "create collection #{quote_name(prefix, name)}"

  defp command({:create_if_not_exists, %Collection{prefix: prefix, name: name}, _}),
    do: "create collection if not exists #{quote_name(prefix, name)}"

  defp command({:alter, %Collection{prefix: prefix, name: name}, _}),
    do: "alter collection #{quote_name(prefix, name)}"

  defp command({:rename, %Collection{} = current_collection, %Collection{} = new_collection}),
    do:
      "rename collection #{quote_name(current_collection.prefix, current_collection.name)} to #{quote_name(new_collection.prefix, new_collection.name)}"

  defp command({:drop, %Collection{prefix: prefix, name: name}}),
    do: "drop collection #{quote_name(prefix, name)}"

  defp command({:drop_if_exists, %Collection{prefix: prefix, name: name}}),
    do: "drop collection if exists #{quote_name(prefix, name)}"

  # Index
  defp command({:create, %Index{prefix: prefix, name: name}}),
    do: "create index #{quote_name(prefix, name)}"

  defp command({:create_if_not_exists, %Index{prefix: prefix, name: name}}),
    do: "create index if not exists #{quote_name(prefix, name)}"

  defp command({:drop, %Index{prefix: prefix, name: name}}),
    do: "drop index #{quote_name(prefix, name)}"

  defp command({:drop_if_exists, %Index{prefix: prefix, name: name}}),
    do: "drop index if exists #{quote_name(prefix, name)}"

  defp quote_name(nil, name), do: quote_name(name)
  defp quote_name(prefix, name), do: quote_name(prefix) <> "." <> quote_name(name)
  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))
  defp quote_name(name), do: name
end
