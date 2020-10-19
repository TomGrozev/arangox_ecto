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

    params = key_from_id(collection, params)

    collection_type = ArangoXEcto.schema_type!(source_module)

    if ArangoXEcto.collection_exists?(conn, collection, collection_type) do
      options =
        if selecting == nil,
          do: [],
          else: [
            write: collection
          ]

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
              [],
              fn resp, acc ->
                acc ++ resp.body["result"]
              end
            )
          end,
          options
        )

      case res do
        {:ok, result} -> {length(result), result}
        {:error, _reason} -> {0, nil}
      end
    else
      {0, []}
    end
  end

  defp key_from_id(source, ids) when is_list(ids) do
    Enum.map(ids, &key_from_id(source, &1))
  end

  defp key_from_id(source, id) when is_binary(id) do
    String.split(id, "/", trim: true)
    |> case do
      [^source | tail] -> tail
      any -> any
    end
    |> List.first()
  end

  defp key_from_id(_, any), do: any
end
