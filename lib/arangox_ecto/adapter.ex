defmodule ArangoXEcto.Adapter do
  @moduledoc """
  Ecto adapter for ArangoDB using ArangoX

  This implements methods for `Ecto.Adapter`. These functions should not be accessed directly
  and should only be used by Ecto. Direct interaction functions are in the `ArangoXEcto` module.
  """

  @otp_app :arangox_ecto

  @behaviour Ecto.Adapter

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    # Maybe something later
    :ok
  end

  # import Bitwise
  # use Bitwise, only_operators: true

  require Logger

  @pool_opts [
    :timeout,
    :pool,
    :pool_size,
    :queue_target,
    :queue_interval,
    :ownership_timeout,
    :repo
  ]

  @doc """
  Initialise adapter with `config`
  """
  @impl Ecto.Adapter
  def init(config) do
    log = Keyword.get(config, :log, :debug)

    valid_log_levels = [
      false,
      :debug,
      :info,
      :notice,
      :warning,
      :error,
      :critical,
      :alert,
      :emergency
    ]

    if log not in valid_log_levels do
      raise """
      invalid value for :log option in Repo config

      The accepted values for the :log option are:
      #{Enum.map_join(valid_log_levels, ", ", &inspect/1)}

      See https://hexdocs.pm/ecto/Ecto.Repo.html for more information.
      """
    end

    stacktrace = Keyword.get(config, :stacktrace, nil)
    telemetry_prefix = Keyword.fetch!(config, :telemetry_prefix)
    telemetry = {config[:repo], log, telemetry_prefix ++ [:query]}

    config = adapter_config(config)
    opts = Keyword.take(config, @pool_opts) |> with_count()
    meta = %{telemetry: telemetry, stacktrace: stacktrace, opts: opts}
    child = Arangox.child_spec(config)

    {:ok, child, meta}
  end

  defp adapter_config(config) do
    if Keyword.has_key?(config, :pool_timeout) do
      message = """
      :pool_timeout option no longer has an effect and has been replaced with an improved queuing system.
      See \"Queue config\" in DBConnection.start_link/2 documentation for more information.
      """

      IO.warn(message)
    end

    config
    |> Keyword.delete(:name)
    |> Keyword.update(:pool, DBConnection.ConnectionPool, &normalize_pool/1)
  end

  defp with_count(opts) do
    properties = opts[:properties] || []
    options = properties[:options] || %{}

    new_properties = Keyword.put(properties, :options, Map.put(options, :fullCount, true))

    Keyword.put(opts, :properties, new_properties)
  end

  defp normalize_pool(pool) do
    if Code.ensure_loaded?(pool) && function_exported?(pool, :unboxed_run, 2) do
      DBConnection.Ownership
    else
      pool
    end
  end

  @doc """
  Ensure all applications necessary to run the adapter are started
  """
  @impl Ecto.Adapter
  def ensure_all_started(config, type) do
    Logger.debug("#{inspect(__MODULE__)}.ensure_all_started", %{
      "#{inspect(__MODULE__)}.ensure_all_started-params" => %{
        type: type,
        config: config
      }
    })

    {:ok, _} = Application.ensure_all_started(@otp_app)

    {:ok, [config]}
  end

  @behaviour Ecto.Adapter.Storage
  @impl true
  defdelegate storage_up(options), to: ArangoXEcto.Behaviour.Storage
  @impl true
  defdelegate storage_status(options), to: ArangoXEcto.Behaviour.Storage
  @impl true
  defdelegate storage_down(options), to: ArangoXEcto.Behaviour.Storage

  @doc """
  Returns true if a connection has been checked out
  """
  @impl Ecto.Adapter
  def checked_out?(adapter_meta) do
    %{pid: pool} = adapter_meta
    get_conn(pool) != nil
  end

  @doc """
  Checks out a connection for the duration of the given function.
  """
  @impl Ecto.Adapter
  def checkout(adapter_meta, opts, callback) do
    checkout_or_transaction(:run, adapter_meta, opts, callback)
  end

  @impl true
  defdelegate autogenerate(field_type), to: ArangoXEcto.Behaviour.Schema

  @doc """
  Returns the loaders of a given type.
  """
  @impl Ecto.Adapter
  def loaders(:uuid, Ecto.UUID), do: [&{:ok, &1}]
  def loaders(:date, _type), do: [&load_date/1]
  def loaders(:time, _type), do: [&load_time/1]
  def loaders(:utc_datetime, _type), do: [&load_utc_datetime/1]
  def loaders(:naive_datetime, _type), do: [&load_naive_datetime/1]
  def loaders(:float, type), do: [&load_float/1, type]
  def loaders(:integer, type), do: [&load_integer/1, type]
  def loaders(:decimal, _type), do: [&load_decimal/1]
  def loaders(_primitive, type), do: [type]

  @doc """
  Returns the dumpers for a given type.
  """
  @impl Ecto.Adapter
  def dumpers(:uuid, Ecto.UUID), do: [&{:ok, &1}]
  def dumpers({:in, sub}, {:in, sub}), do: [{:array, sub}]

  def dumpers(:date, type) when type in [:date, Date],
    do: [fn %Date{} = d -> {:ok, Date.to_iso8601(d)} end]

  def dumpers(:time, type) when type in [:time, Time],
    do: [fn %Time{} = t -> {:ok, Time.to_iso8601(t)} end]

  def dumpers(:utc_datetime, type) when type in [:utc_datetime, DateTime],
    do: [fn %DateTime{} = dt -> {:ok, DateTime.to_iso8601(dt)} end]

  def dumpers(:naive_datetime, type) when type in [:naive_datetime, NaiveDateTime],
    do: [fn %NaiveDateTime{} = dt -> {:ok, NaiveDateTime.to_iso8601(dt)} end]

  def dumpers(:decimal, type) when type in [:decimal, Decimal],
    do: [fn %Decimal{} = d -> {:ok, Decimal.to_string(d)} end]

  def dumpers(_primitive, type), do: [type]

  @behaviour Ecto.Adapter.Queryable
  @impl true
  defdelegate stream(adapter_meta, query_meta, query_cache, params, options),
    to: ArangoXEcto.Behaviour.Queryable

  @impl true
  defdelegate prepare(atom, query), to: ArangoXEcto.Behaviour.Queryable

  @impl true
  defdelegate execute(adapter_meta, query_meta, query_cache, params, options),
    to: ArangoXEcto.Behaviour.Queryable

  @behaviour Ecto.Adapter.Schema
  @impl true
  defdelegate delete(adapter_meta, schema_meta, filters, returning, options),
    to: ArangoXEcto.Behaviour.Schema

  @impl true
  defdelegate insert(adapter_meta, schema_meta, fields, on_conflict, returning, options),
    to: ArangoXEcto.Behaviour.Schema

  @impl true
  defdelegate insert_all(
                adapter_meta,
                schema_meta,
                header,
                list,
                on_conflict,
                returning,
                placeholders,
                options
              ),
              to: ArangoXEcto.Behaviour.Schema

  @impl true
  defdelegate update(adapter_meta, schema_meta, fields, filters, returning, options),
    to: ArangoXEcto.Behaviour.Schema

  @behaviour Ecto.Adapter.Transaction
  @impl true
  defdelegate in_transaction?(adapter_meta),
    to: ArangoXEcto.Behaviour.Transaction

  @impl true
  defdelegate transaction(adapter_meta, options, function),
    to: ArangoXEcto.Behaviour.Transaction

  @impl true
  defdelegate rollback(adapter_meta, value),
    to: ArangoXEcto.Behaviour.Transaction

  def lock_with_migrations(_, _, _), do: []

  @doc """
  Receives a DDL command and executes it
  """
  @spec execute_ddl(
          Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          ArangoXEcto.Migration.command(),
          Keyword.t()
        ) ::
          {:ok, [{Logger.level(), any(), Keyword.t()}]}
  def execute_ddl(repo, command, opts) when is_atom(repo),
    do: execute_ddl(Ecto.Adapter.lookup_meta(repo), command, opts)

  def execute_ddl(meta, command, opts) do
    logs = ArangoXEcto.Migrator.execute_command(meta, command, opts)

    {:ok, List.wrap(logs)}
  end

  @doc false
  def reduce(adapter_meta, statement, params, opts, acc, fun) do
    %{pid: pool, telemetry: telemetry, opts: default_opts} = adapter_meta
    opts = with_log(telemetry, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        Arangox.cursor(conn, statement, params, opts)
        |> Enumerable.reduce(acc, fun)

      _ ->
        raise "cannot reduce stream outside of transaction"
    end
  end

  @doc false
  def into(adapter_meta, statement, params, opts) do
    %{pid: pool, telemetry: telemetry, opts: default_opts} = adapter_meta
    opts = with_log(telemetry, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        Arangox.cursor(conn, statement, params, opts)
        |> Collectable.into()

      _ ->
        raise "cannot collect into stream outside of transaction"
    end
  end

  @doc false
  def load_integer(arg) when is_number(arg), do: {:ok, trunc(arg)}
  def load_integer(nil), do: {:ok, nil}
  def load_integer(_), do: :error

  @doc false
  def load_float(arg) when is_number(arg), do: {:ok, :erlang.float(arg)}
  def load_float(nil), do: {:ok, nil}
  def load_float(_), do: :error

  @doc false
  def load_decimal(nil), do: {:ok, nil}
  def load_decimal(arg), do: {:ok, Decimal.new(arg)}

  # Connection helpers

  @doc false
  def checkout_or_transaction(func, adapter_meta, opts, callback)
      when func in [:transaction, :run] do
    %{pid: pool, telemetry: telemetry, opts: default_opts} = adapter_meta

    opts =
      with_log(telemetry, [], opts ++ default_opts)
      |> process_sources()

    callback = fn conn ->
      previous_conn = put_conn(pool, conn)

      try do
        if Keyword.get(Function.info(callback), :arity) == 1 do
          callback.(conn)
        else
          callback.()
        end
      after
        reset_conn(pool, previous_conn)
      end
    end

    apply(Arangox, func, [get_conn_or_pool(pool), callback, opts])
  end

  @doc false
  def get_database(repo, opts) do
    Keyword.get(
      opts,
      :database,
      ArangoXEcto.get_prefix_database(repo, Keyword.get(opts, :prefix))
    )
  end

  @doc false
  def get_conn_from_repo(repo_or_conn) do
    case repo_or_conn do
      pid when is_pid(pid) ->
        pid

      repo ->
        %{pid: pool} = Ecto.Adapter.lookup_meta(repo)

        pool
    end
    |> get_conn_or_pool()
  end

  @doc false
  def get_conn(pool) do
    Process.get(key(pool))
  end

  @doc false
  def get_conn_or_pool(pool) do
    Process.get(key(pool), pool)
  end

  defp put_conn(pool, conn) do
    Process.put(key(pool), conn)
  end

  defp reset_conn(pool, conn) do
    if conn do
      put_conn(pool, conn)
    else
      Process.delete(key(pool))
    end
  end

  defp key(pool), do: {__MODULE__, pool}

  ## Logging

  @doc false
  def with_log(telemetry, params, opts) do
    if Keyword.get(opts, :log) |> is_function() do
      opts
    else
      [log: &log(telemetry, params, &1, opts)] ++ opts
    end
  end

  defp log({repo, log, event_name}, params, entry, opts) do
    %{
      connection_time: query_time,
      decode_time: decode_time,
      pool_time: queue_time,
      idle_time: idle_time,
      result: result,
      query: query,
      call: call
    } = entry

    source = Keyword.get(opts, :source)
    type = Keyword.get(opts, :type, "query")
    query = Keyword.get(opts, :query, process_query(query))
    result = with {:ok, _query, res} <- result, do: {:ok, res}
    stacktrace = Keyword.get(opts, :stacktrace)
    log_params = opts[:cast_params] || params

    acc = if idle_time, do: [idle_time: idle_time], else: []

    measurements =
      log_measurements(
        [query_time: query_time, decode_time: decode_time, queue_time: queue_time],
        0,
        acc
      )

    metadata = %{
      type: :arangox_ecto_query,
      repo: repo,
      result: result,
      params: params,
      cast_params: opts[:cast_params],
      query: query,
      source: source,
      stacktrace: stacktrace,
      options: Keyword.get(opts, :telemetry_options, [])
    }

    if event_name = Keyword.get(opts, :telemtry_event, event_name) do
      :telemetry.execute(event_name, measurements, metadata)
    end

    case {opts[:log], log} do
      {false, _level} ->
        :ok

      {opts_level, false} when opts_level in [nil, true] ->
        :ok

      {true, level} ->
        Logger.log(
          level,
          fn ->
            log_iodata(
              {type, call},
              measurements,
              repo,
              source,
              query,
              log_params,
              result,
              stacktrace
            )
          end,
          ansi_color: aql_colour(query)
        )

      {opts_level, args_level} ->
        Logger.log(
          opts_level || args_level,
          fn ->
            log_iodata(
              {type, call},
              measurements,
              repo,
              source,
              query,
              log_params,
              result,
              stacktrace
            )
          end,
          ansi_color: aql_colour(query)
        )
    end

    :ok
  end

  defp process_query(%Arangox.Request{method: method, path: path, headers: headers}) do
    "(#{Atom.to_string(method) |> String.upcase()}) (Path: #{path}) (Header: #{inspect(headers)})"
  end

  defp process_query(query), do: String.Chars.to_string(query)

  defp log_measurements([{_, nil} | rest], total, acc),
    do: log_measurements(rest, total, acc)

  defp log_measurements([{key, value} | rest], total, acc),
    do: log_measurements(rest, total + value, [{key, value} | acc])

  defp log_measurements([], total, acc),
    do: Map.new([total_time: total] ++ acc)

  defp log_iodata({type, call}, measurements, repo, source, query, params, result, stacktrace) do
    [
      String.upcase(type),
      log_call(call),
      ?\s,
      log_ok_error(result),
      log_ok_source(source),
      log_time("db", measurements, :query_time, true),
      log_time("decode", measurements, :decode_time, false),
      log_time("queue", measurements, :queue_time, false),
      log_time("idle", measurements, :idle_time, true),
      log_query(query, params, call),
      log_stacktrace(stacktrace, repo)
    ]
  end

  defp log_call(call) when call in [:declare, :fetch, :deallocate],
    do: " [#{String.upcase(Atom.to_string(call))}]"

  defp log_call(_), do: ""

  defp log_query(_query, _params, call) when call in [:fetch, :deallocate], do: ""

  defp log_query(query, params, _call) do
    [
      ?\n,
      query,
      ?\n,
      inspect(params, charlists: false)
    ]
  end

  defp log_ok_error({:ok, _res}), do: "OK"
  defp log_ok_error({:error, _err}), do: "ERROR"

  defp log_ok_source(nil), do: ""
  defp log_ok_source(source), do: " source=#{inspect(source)}"

  defp log_time(label, measurements, key, force) do
    case Map.fetch(measurements, key) do
      {:ok, time} ->
        us = System.convert_time_unit(time, :native, :microsecond)
        ms = div(us, 100) / 10

        if force or ms > 0 do
          [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
        else
          []
        end

      :error ->
        []
    end
  end

  defp log_stacktrace(stacktrace, repo) do
    with [_ | _] <- stacktrace,
         {module, function, arity, info} <- last_non_ecto(Enum.reverse(stacktrace), repo, nil) do
      [
        ?\n,
        IO.ANSI.light_black(),
        "↳ ",
        Exception.format_mfa(module, function, arity),
        log_stacktrace_info(info),
        IO.ANSI.reset()
      ]
    else
      _ -> []
    end
  end

  defp log_stacktrace_info([file: file, line: line] ++ _) do
    [", at: ", file, ?:, Integer.to_string(line)]
  end

  defp log_stacktrace_info(_), do: []

  @repo_modules [Ecto.Repo.Queryable, Ecto.Repo.Schema, Ecto.Repo.Transaction]

  defp last_non_ecto([{mod, _, _, _} | _stacktrace], repo, last)
       when mod == repo or mod in @repo_modules,
       do: last

  defp last_non_ecto([last | stacktrace], repo, _last), do: last_non_ecto(stacktrace, repo, last)
  defp last_non_ecto([], _repo, last), do: last

  defp aql_colour("FOR" <> _), do: :cyan
  defp aql_colour(_), do: nil

  defp load_date(nil), do: {:ok, nil}

  defp load_date(d) do
    case Date.from_iso8601(d) do
      {:ok, res} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  defp load_time(nil), do: {:ok, nil}

  defp load_time(t) do
    case Time.from_iso8601(t) do
      {:ok, res} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  defp load_utc_datetime(nil), do: {:ok, nil}

  defp load_utc_datetime(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, res, _} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  defp load_naive_datetime(nil), do: {:ok, nil}

  defp load_naive_datetime(dt) do
    case NaiveDateTime.from_iso8601(dt) do
      {:ok, res} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  @sources_keys [:write, :read, :exclusive]
  defp process_sources(opts) do
    opts
    |> Enum.map(fn
      {k, v} when is_list(v) and k in @sources_keys ->
        {k, Enum.map(v, &convert_source/1)}

      {k, v} when k in @sources_keys ->
        {k, convert_source(v)}

      v ->
        v
    end)
  end

  defp convert_source(source) when is_binary(source), do: source

  defp convert_source(source) when is_atom(source), do: source.__schema__(:source)
end
