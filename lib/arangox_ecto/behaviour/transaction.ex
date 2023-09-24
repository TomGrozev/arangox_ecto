defmodule ArangoXEcto.Behaviour.Transaction do
  @moduledoc false

  alias ArangoXEcto.Adapter

  @behaviour Ecto.Adapter.Transaction

  @impl true
  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, Adapter.get_conn(pool))
  end

  @impl true
  def transaction(%{pid: pool}, opts, callback) do
    callback = fn conn ->
      previous_conn = Adapter.put_conn(pool, conn)

      try do
        callback.()
      after
        Adapter.reset_conn(pool, previous_conn)
      end
    end

    Arangox.transaction(Adapter.get_conn_or_pool(pool), callback, opts)
  end

  @impl true
  def rollback(%{pid: pool}, value) do
    case Adapter.get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn -> Arangox.abort(conn, value)
      _ -> raise "cannot call rollback outside of transaction"
    end
  end
end
