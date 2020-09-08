defmodule ArangoXEcto.Behaviour.Queryable do
  @moduledoc """
  Handles Ecto adapter queryable methods
  """

  require Logger

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

    IO.inspect(query)

    aql_query = apply(ArangoXEcto.Query, cmd, [query])
    {:nocache, aql_query}
  end

  @doc """
  Executes a previously prepared query.
  """
  @impl true
  def execute(
        %{pid: conn},
        %{sources: {{collection, _, _}}, select: selecting},
        {:nocache, query},
        params,
        _options
      ) do
    Logger.debug("#{inspect(__MODULE__)}.execute", %{
      "#{inspect(__MODULE__)}.execute-params" => %{
        query: inspect(query, structs: false)
      }
    })

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
      |> IO.inspect()
      # TODO: Filter for relationships and query the edges

    case res do
      {:ok, result} -> {length(result), result}
      {:error, _reason} -> {0, nil}
    end
  end
end
