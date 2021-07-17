defmodule ArangoXEcto.Behaviour.Queryable do
  @moduledoc false

  require Logger

  @behaviour Ecto.Adapter.Queryable

  @doc """
  Streams a previously prepared query.
  """
  @impl true
  def stream(_adapter_meta, _query_meta, _query, _params, _options) do
    raise "#{inspect(__MODULE__)}.stream: #{inspect(__MODULE__)} does not currently support stream"
  end

  @doc """
  Commands invoked to prepare a query.
  It is used on Ecto.Repo.all/2, Ecto.Repo.update_all/3, and Ecto.Repo.delete_all/2.
  """
  @impl true
  def prepare(cmd, query) do
    Logger.debug("#{inspect(__MODULE__)}.prepare: #{cmd}", %{
      "#{inspect(__MODULE__)}.prepare-params" => %{
        query: inspect(query, structs: false)
      }
    })

    aql_query = apply(ArangoXEcto.Query, cmd, [query])
    {:nocache, aql_query}
  end

  @doc """
  Executes a previously prepared query.
  """
  @impl true
  def execute(
        %{pid: conn},
        %{sources: {{collection, source_module, _}}, select: selecting},
        {:nocache, query},
        params,
        _options
      ) do
    Logger.debug("#{inspect(__MODULE__)}.execute", %{
      "#{inspect(__MODULE__)}.execute-params" => %{
        query: inspect(query, structs: false)
      }
    })

    collection_type = ArangoXEcto.schema_type(source_module)

    write_operation = selecting != nil or String.match?(query, ~r/^.*[update|delete].*+$/i)

    if ArangoXEcto.collection_exists?(conn, collection, collection_type) do
      options =
        if write_operation,
          do: [
            write: collection
          ],
          else: []

      zipped_args =
        Stream.zip(
          Stream.iterate(1, &(&1 + 1))
          |> Stream.map(&Integer.to_string(&1)),
          params
        )
        |> Enum.into(%{})

      res =
        Arangox.transaction(
          conn,
          fn cursor ->
            stream = Arangox.cursor(cursor, query, zipped_args)

            Enum.reduce(
              stream,
              {0, []},
              fn resp, {_len, acc} ->
                len =
                  case write_operation do
                    true -> resp.body["extra"]["stats"]["writesExecuted"]
                    false -> resp.body["extra"]["stats"]["scannedFull"]
                  end

                {len, acc ++ resp.body["result"]}
              end
            )
          end,
          options
        )

      case res do
        {:ok, {len, result}} -> {len, result}
        {:error, _reason} -> {0, nil}
      end
    else
      {0, []}
    end
  end
end
