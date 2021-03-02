defmodule ArangoXEcto.Behaviour.Transaction do
  @moduledoc false

  @behaviour Ecto.Adapter.Transaction

  @impl true
  def in_transaction?(%{pid: conn}) do
    match?(%DBConnection{conn_mode: :transaction}, conn)
  end

  @impl true
  def transaction(%{pid: conn}, opts, callback) do
    callback = fn _c ->
      callback.()
    end

    Arangox.transaction(conn, callback, opts)
  end

  @impl true
  def rollback(_adapter_meta, _value),
    do: throw("ArangoXEcto does not support rollbacks at this time")
end
