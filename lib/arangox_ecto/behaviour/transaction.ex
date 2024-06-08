defmodule ArangoXEcto.Behaviour.Transaction do
  @moduledoc false

  alias ArangoXEcto.Adapter

  @behaviour Ecto.Adapter.Transaction

  @impl true
  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, Adapter.get_conn(pool))
  end

  @impl true
  def transaction(adapter_meta, opts, callback) do
    Adapter.checkout_or_transaction(:transaction, adapter_meta, opts, callback)
  end

  @impl true
  def rollback(%{pid: pool}, value) do
    case Adapter.get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn -> Arangox.abort(conn, value)
      _ -> raise "cannot call rollback outside of transaction"
    end
  end
end
