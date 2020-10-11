defmodule ArangoXEcto.Behaviour.Storage do
  @moduledoc """
  Handles Ecto adapter storage methods

  This implements methods for `Ecto.Adapter.Storage`. These functions should not be accessed directly
  and should only be used by Ecto. Direct interaction functions are in the `ArangoXEcto` module.
  """
  @moduledoc false

  @behaviour Ecto.Adapter.Storage

  alias ArangoXEcto.Utils

  @doc """
  Creates the storage given by options.
  """
  @impl true
  def storage_up(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    database = Keyword.fetch!(options, :database)
    {:ok, _} = ArangoXEcto.Adapter.ensure_all_started(otp_app, :temporary)
    {:ok, conn} = Utils.get_system_db(options)

    case Arangox.post(conn, "/_api/database", %{name: database}) do
      {:ok, _, _} -> :ok
      {:error, %{status: status}} -> {:error, status}
    end
  end

  @doc """
  Returns the status of a storage given by options.
  """
  @impl true
  def storage_status(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    database = Keyword.fetch!(options, :database)
    {:ok, _} = ArangoXEcto.Adapter.ensure_all_started(otp_app, :temporary)
    {:ok, conn} = Utils.get_system_db(options)

    case Arangox.get(conn, "/_api/database") do
      {:ok, _, %{body: %{"result" => result}}} when is_list(result) ->
        if database in result do
          :ok
        else
          :down
        end

      {:error, %{status: status}} ->
        {:error, status}
    end
  end

  @doc """
  Drops the storage given by options.
  """
  @impl true
  def storage_down(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    database = Keyword.fetch!(options, :database)
    {:ok, _} = ArangoXEcto.Adapter.ensure_all_started(otp_app, :temporary)
    {:ok, conn} = Utils.get_system_db(options)

    case Arangox.delete(conn, "/_api/database/#{database}") do
      {:ok, _, _} -> :ok
      {:error, %{status: status}} -> {:error, status}
    end
  end
end
