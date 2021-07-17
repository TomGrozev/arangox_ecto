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
        %{sources: sources, select: selecting},
        {:nocache, query},
        params,
        _options
      ) do
    Logger.debug("#{inspect(__MODULE__)}.execute", %{
      "#{inspect(__MODULE__)}.execute-params" => %{
        query: inspect(query, structs: false)
      }
    })

    is_write_operation = selecting != nil or String.match?(query, ~r/^.*[update|delete].*+$/i)

    {run_query, options} = process_sources(conn, sources, is_write_operation)

    # TODO: Make collection checking optional in config or options
    if run_query do
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
                  case is_write_operation do
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

  defp process_sources(conn, sources, is_write_operation) do
    sources = Tuple.to_list(sources)
    run_query = ensure_all_collections_exist(conn, sources)

    {run_query, build_options(sources, is_write_operation)}
  end

  defp build_options(sources, is_write_operation) do
    collections = Enum.map(sources, fn {collection, _, _} -> collection end)

    if is_write_operation, do: [write: collections], else: []
  end

  defp ensure_all_collections_exist(conn, sources) when is_list(sources) do
    sources
    |> Enum.reduce(true, fn {collection, source_module, _}, acc ->
      if acc do
        collection_type = ArangoXEcto.schema_type(source_module)
        acc && ArangoXEcto.collection_exists?(conn, collection, collection_type)
      else
        acc
      end
    end)
  end
end
