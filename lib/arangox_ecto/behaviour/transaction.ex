defmodule ArangoXEcto.Behaviour.Transaction do
  @moduledoc false

  @behaviour Ecto.Adapter.Transaction

  @impl true
  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, get_conn(pool))
  end

  @impl true
  def transaction(%{pid: pool}, opts, callback) do
    callback = fn conn ->
      previous_conn = put_conn(pool, conn)

      try do
        callback.()
      after
        reset_conn(pool, previous_conn)
      end
    end

    Arangox.transaction(get_conn_or_pool(pool), callback, opts)
  end

  @impl true
  def rollback(%{pid: pool}, value) do
    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn -> Arangox.abort(conn, value)
      _ -> raise "cannot call rollback outside of transaction"
    end
  end

  defp get_conn_or_pool(pool) do
    Process.get(key(pool), pool)
  end

  defp get_conn(pool) do
    Process.get(key(pool))
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
end
