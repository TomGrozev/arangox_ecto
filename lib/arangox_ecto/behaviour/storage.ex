defmodule ArangoXEcto.Behaviour.Storage do
  @moduledoc false

  @behaviour Ecto.Adapter.Storage

  @default_maintenance_database "_system"

  @doc """
  Creates the storage given by opts.
  """
  @impl true
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository config"

    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    fun = fn conn, opts -> Arangox.post(conn, "/_api/database", %{name: database}, opts) end

    case run_query(fun, opts) do
      {:ok, _} -> :ok
      {:error, %{error_num: 1207}} -> {:error, :already_up}
      {:error, reason} -> {:error, Exception.message(reason)}
    end
  end

  @doc """
  Returns the status of a storage given by options.
  """
  @impl true
  def storage_status(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository config"

    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    fun = fn conn, opts -> Arangox.get(conn, "/_api/database", opts) end

    case run_query(fun, opts) do
      {:ok, %{body: %{"result" => dbs}}} ->
        if database in dbs, do: :up, else: :down

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Drops the storage given by options.
  """
  @impl true
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository config"

    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    fun = fn conn, opts -> Arangox.delete(conn, "/_api/database/#{database}", opts) end

    case run_query(fun, opts) do
      {:ok, _} -> :ok
      {:error, %{error_num: 1228}} -> {:error, :already_down}
      {:error, reason} -> {:error, Exception.message(reason)}
    end
  end

  defp run_query(fun, opts) do
    {:ok, _} = Application.ensure_all_started(:arangox_ecto)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size, :telemetry_prefix])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    task =
      Task.Supervisor.async_nolink(ArangoXEcto.StorageSupervisor, fn ->
        {:ok, conn} = Arangox.start_link(opts)

        value = fun.(conn, opts)
        GenServer.stop(conn)
        value
      end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, error}} ->
        {:error, error}

      {:exit, {%{__struct__: struct} = error, _}}
      when struct in [Arangox.Error, DBConnection.Error] ->
        {:error, error}

      {:exit, reason} ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}

      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end
end
