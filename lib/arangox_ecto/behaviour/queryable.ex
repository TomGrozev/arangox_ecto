defmodule ArangoXEcto.Behaviour.Queryable do
  @moduledoc false

  @behaviour Ecto.Adapter.Queryable

  @doc """
  Streams a query.

  This utalises the `Arangox.cursor/4` implementation that ultimately
  uses the `DBConnection.Stream` implementation.
  """
  @impl true
  def stream(adapter_meta, _query_meta, query, params, opts) do
    do_stream(adapter_meta, query, params, opts)
  end

  @doc """
  Commands invoked to prepare a query.
  It is used on Ecto.Repo.all/2, Ecto.Repo.update_all/3, and Ecto.Repo.delete_all/2.
  """
  @impl true
  def prepare(cmd, query) do
    aql_query = apply(ArangoXEcto.Query, cmd, [query])

    {:cache, {System.unique_integer([:positive]), aql_query}}
  end

  @doc """
  Executes a previously prepared query.
  """
  @impl true
  def execute(adapter_meta, query_meta, {:cache, update, {id, prepared}}, params, opts) do
    is_write_operation = String.match?(prepared, ~r/(update|remove) .+/i)

    case aql_call(
           adapter_meta,
           prepared,
           params,
           build_options(opts, query_meta, is_write_operation)
         ) do
      {:ok, res} ->
        update.({id, prepared})
        res

      {:error, err} ->
        raise err
    end
  end

  def execute(adapter_meta, query_meta, {:cached, update, _reset, {id, cached}}, params, opts) do
    is_write_operation = String.match?(cached, ~r/(update|remove) .+/i)

    case aql_call(
           adapter_meta,
           cached,
           params,
           build_options(opts, query_meta, is_write_operation)
         ) do
      {:ok, res} ->
        update.({id, cached})
        res

      {:error, err} ->
        raise err
    end
  end

  def execute(adapter_meta, query_meta, {:nocache, {_id, prepared}}, params, opts) do
    is_write_operation = String.match?(prepared, ~r/(update|remove) .+/i)

    case aql_call(
           adapter_meta,
           prepared,
           params,
           build_options(opts, query_meta, is_write_operation)
         ) do
      {:ok, res} ->
        res

      {:error, err} ->
        raise err
    end
  end

  defp build_options(opts, %{sources: sources}, is_write) do
    sources = Tuple.to_list(sources)

    Keyword.put(opts, :sources, sources)
    |> maybe_put_write_sources(sources, is_write)
  end

  defp maybe_put_write_sources(opts, _sources, false), do: opts

  defp maybe_put_write_sources(opts, sources, true) do
    Keyword.put(opts, :write, Enum.map(sources, fn {collection, _, _} -> collection end))
  end

  defp do_stream(adapter_meta, {:cache, _, {_id, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp do_stream(adapter_meta, {:cached, _, _, {_id, cached}}, params, opts) do
    prepare_stream(adapter_meta, String.Chars.to_string(cached), params, opts)
  end

  defp do_stream(adapter_meta, {:nocache, {_id, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp prepare_stream(adapter_meta, prepared, params, opts) do
    adapter_meta
    |> ArangoXEcto.Behaviour.Stream.build(prepared, params, opts)
    |> Stream.map(fn %Arangox.Response{
                       body: %{
                         "extra" => %{"stats" => %{"cursorsCreated" => nrows}},
                         "result" => rows
                       }
                     } ->
      {nrows, rows}
    end)
  end

  defp aql_call(%{repo: repo}, query, params, opts) do
    is_static = Keyword.get(repo.config(), :static, true)

    zipped_args =
      Enum.zip(
        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(&Integer.to_string(&1)),
        params
      )

    ensure_all_views_exist(repo, Keyword.get(opts, :sources, []), is_static)

    case ArangoXEcto.aql_query(repo, query, zipped_args, opts) do
      {:error, %Arangox.Error{status: 404, error_num: 1203}} when not is_static ->
        {:ok, {0, []}}

      any ->
        any
    end
  end

  defp ensure_all_views_exist(repo, sources, is_static) when is_list(sources) do
    for {collection, source_module, _} <- sources do
      if ArangoXEcto.view?(source_module) do
        maybe_create_view(repo, {collection, source_module}, is_static)
      end
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
