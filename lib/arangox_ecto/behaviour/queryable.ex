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
        %{pid: conn, repo: repo},
        %{sources: sources},
        {:nocache, query},
        params,
        opts
      ) do
    Logger.debug("#{inspect(__MODULE__)}.execute", %{
      "#{inspect(__MODULE__)}.execute-params" => %{
        query: inspect(query, structs: false)
      }
    })

    is_write_operation = String.match?(query, ~r/(update|remove) .+/i)
    is_static = Keyword.get(repo.config(), :static, false)

    database =
      opts
      |> Keyword.get(:prefix)
      |> then(&ArangoXEcto.get_prefix_database(repo, &1))

    {run_query, options} = process_sources(repo, sources, is_static, is_write_operation)

    dumped_params = Enum.map(params, &dump/1)

    if run_query do
      zipped_args =
        Stream.zip(
          Stream.iterate(1, &(&1 + 1))
          |> Stream.map(&Integer.to_string(&1)),
          dumped_params
        )
        |> Enum.into(%{})

      res =
        Arangox.transaction(
          conn,
          fn cursor ->
            stream = Arangox.cursor(cursor, query, zipped_args, database: database)

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
          Keyword.put(options, :database, database)
        )

      case res do
        {:ok, {len, result}} -> {len, result}
        {:error, _reason} -> {0, nil}
      end
    else
      {0, []}
    end
  end

  defp dump(list_type) when is_list(list_type), do: Enum.map(list_type, &dump/1)
  defp dump(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp dump(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp dump(%Time{} = dt), do: Time.to_iso8601(dt)
  defp dump(%Date{} = dt), do: Date.to_iso8601(dt)
  defp dump(%Decimal{} = d), do: Decimal.to_string(d)
  defp dump(val), do: val

  defp process_sources(repo, sources, is_static, is_write_operation) do
    sources = Tuple.to_list(sources)
    run_query = ensure_all_collections_exist(repo, sources, is_static)

    {run_query, build_options(sources, is_write_operation)}
  end

  defp build_options(sources, is_write_operation) do
    collections = Enum.map(sources, fn {collection, _, _} -> collection end)

    if is_write_operation, do: [write: collections], else: []
  end

  defp ensure_all_collections_exist(repo, sources, is_static) when is_list(sources) do
    sources
    |> Enum.all?(fn {collection, source_module, _} ->
      case ArangoXEcto.schema_type(source_module) do
        :view ->
          maybe_create_view(repo, {collection, source_module}, is_static)

          true

        collection_type ->
          maybe_raise_collection_error(repo, collection, collection_type, is_static)
      end
    end)
  end

  defp maybe_raise_collection_error(repo, collection, collection_type, is_static) do
    cond do
      ArangoXEcto.collection_exists?(repo, collection, collection_type) ->
        true

      is_static ->
        raise("Collection (#{collection}) does not exist. Maybe a migration is missing.")

      true ->
        false
    end
  end

  defp maybe_create_view(repo, {source, schema}, is_static) do
    cond do
      ArangoXEcto.view_exists?(repo, source) ->
        true

      is_static ->
        raise("View (#{schema}) does not exist. Maybe a migration is missing.")

      true ->
        ArangoXEcto.create_view(repo, schema)
    end
  end
end
