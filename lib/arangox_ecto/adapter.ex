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

  @doc """
  Starts the Agent with an empty list
  """
  def start_link({_module, config}) do
    Logger.debug(
      "#{inspect(__MODULE__)}.start_link",
      %{
        "#{inspect(__MODULE__)}.start_link-params" => %{
          config: config
        }
      }
    )

    Agent.start_link(fn -> [] end)
  end

  @doc """
  Initialise adapter with `config`
  """
  @impl Ecto.Adapter
  def init(config) do
    child = Arangox.child_spec(config)

    # Maybe something here later
    meta = %{}

    {:ok, child, meta}
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
  def checked_out?(_adapter_meta) do
    Logger.debug(
      "#{inspect(__MODULE__)}.checked_out?: #{inspect(__MODULE__)} does not currently support checkout"
    )

    false
  end

  @doc """
  Checks out a connection for the duration of the given function.
  """
  @impl Ecto.Adapter
  def checkout(_meta, _opts, _fun) do
    raise "#{inspect(__MODULE__)}.checkout: #{inspect(__MODULE__)} does not currently support checkout"
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
  def loaders(:naive_datetime, _type), do: [&NaiveDateTime.from_iso8601/1]
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
  defdelegate delete(adapter_meta, schema_meta, filters, options),
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

  #  defp validate_struct(module, %{} = params),
  #    do: module.changeset(struct(module.__struct__), params)

  defp load_date(d) do
    case Date.from_iso8601(d) do
      {:ok, res} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  defp load_time(t) do
    case Time.from_iso8601(t) do
      {:ok, res} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  defp load_utc_datetime(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, res, _} -> {:ok, res}
      {:error, _reason} -> :error
    end
  end

  def load_integer(arg) when is_number(arg), do: {:ok, trunc(arg)}
  def load_integer(_), do: :error

  def load_float(arg) when is_number(arg), do: {:ok, :erlang.float(arg)}
  def load_float(_), do: :error

  def load_decimal(arg), do: {:ok, Decimal.new(arg)}
end
