defmodule ArangoXEcto.Behaviour.Schema do
  @moduledoc """
  Handles Ecto adapter schema methods
  """

  @behaviour Ecto.Adapter.Schema

  require Logger

  @doc """
  Called to autogenerate a value for id/embed_id/binary_id.

  Returns nil since we want to use an id generated by arangodb
  """
  @impl true
  def autogenerate(:id), do: raise("ArangoDB does not support type :id")
  def autogenerate(:embed_id), do: Ecto.UUID.generate()
  def autogenerate(:binary_id), do: nil

  @doc """
  Inserts a single new struct in the data store.
  """
  @impl true
  def insert(
        %{pid: conn},
        %{source: collection, schema: schema} = a,
        fields,
        on_conflict,
        returning,
        options
      ) do
    #    IO.inspect(a)
    #    IO.inspect(fields)
    #    IO.inspect(on_conflict)
    #    IO.inspect(returning)
    #    IO.inspect(options)

    return_new = should_return_new?(returning, options)
    options = if return_new, do: "?returnNew=true", else: ""

    foreign_keys = get_foreign_keys(schema)

    insert_fields =
      fields
      |> Keyword.drop(foreign_keys)

    doc = Enum.into(insert_fields, %{})

    Logger.debug("#{inspect(__MODULE__)}.insert", %{
      "#{inspect(__MODULE__)}.insert-params" => %{document: inspect(doc)}
    })

    Arangox.post(
      conn,
      "/_api/document/#{collection}" <> options,
      doc
    )
    |> single_doc_result(returning, return_new)
  end

  @doc """
  Inserts multiple entries into the data store.
  """
  @impl true
  def insert_all(
        %{pid: conn},
        %{source: collection},
        _header,
        list,
        _on_conflict,
        returning,
        options
      ) do
    docs = build_docs(list)
    return_new = should_return_new?(returning, options)
    options = if return_new, do: "?returnNew=true", else: ""

    case Arangox.post(
           conn,
           "/_api/document/#{collection}" <> options,
           docs
         ) do
      {:ok, _, %{body: body}} ->
        get_insert_fields(body, returning, return_new)

      {:error, %{status: status}} ->
        {:invalid, status}
    end
  end

  @doc """
  Deletes a single struct with the given filters.
  """
  @impl true
  def delete(%{pid: conn}, %{source: collection}, [{:_key, key}], _options) do
    case Arangox.delete(conn, "/_api/document/#{collection}/#{key}") do
      {:ok, _, _} -> {:ok, []}
      {:error, %{status: status}} -> {:error, status}
    end
  end

  def delete(_adapter_meta, _schema_meta, _filters, _options) do
    # TODO: Do this
    raise "Deleting with filters other than _key is not supported yet"
  end

  @doc """
  Updates a single struct with the given filters.
  """
  @impl true
  def update(%{pid: conn}, %{source: collection}, fields, [{:_key, key}], returning, options) do
    document = Enum.into(fields, %{})
    IO.inspect(options)

    return_new = should_return_new?(returning, options)
    options = if return_new, do: "?returnNew=true", else: ""

    Arangox.patch(
      conn,
      "/_api/document/#{collection}/#{key}" <> options,
      document
    )
    |> single_doc_result(returning, return_new)
  end

  def update(_adapter_meta, _schema_meta, _fields, _filters, _returning, _options) do
    # TODO: Do this
    raise "Updating with filters other than _key is not supported yet"
  end

  @spec get_foreign_keys(nil | module()) :: [atom()]
  def get_foreign_keys(nil), do: []

  def get_foreign_keys(schema) do
    Enum.map(schema.__schema__(:associations), fn assoc ->
      schema.__schema__(:association, assoc)
    end)
    |> Enum.filter(fn
      %Ecto.Association.BelongsTo{} -> true
      _ -> false
    end)
    |> Enum.map(&Map.get(&1, :owner_key))
  end

  defp should_return_new?(returning, options) do
    Keyword.get(options, :return_new, false) or
      Enum.any?(returning, &(not (&1 in [:_id, :_key, :_rev])))
  end

  defp single_doc_result({:ok, _, %Arangox.Response{body: %{"new" => doc}}}, returning, true) do
    {:ok, Enum.map(returning, &{&1, Map.get(doc, Atom.to_string(&1))})}
  end

  defp single_doc_result({:ok, _, %Arangox.Response{body: doc}}, returning, false) do
    doc = patch_body_keys(doc)
    {:ok, Enum.map(returning, &{&1, Map.get(doc, Atom.to_string(&1))})}
  end

  defp single_doc_result({:error, %{error_num: 1210, message: msg}}, _, _) do
    {:invalid, [unique: msg]}
  end

  defp single_doc_result({:error, %{error_num: error_num, message: msg}}, _, _) do
    raise "#{inspect(__MODULE__)} Error(#{error_num}): #{msg}"
  end

  defp build_docs(fields) when is_list(fields) do
    Enum.map(
      fields,
      fn
        %{} = doc -> doc
        doc when is_list(doc) -> Enum.into(doc, %{})
      end
    )
  end

  defp patch_body_keys(%{} = body) do
    for {k, v} <- body, into: %{}, do: {replacement_key(k), v}
  end

  defp get_insert_fields(docs, returning, false), do: process_docs(docs, returning)

  defp get_insert_fields(docs, returning, true) do
    process_docs(Enum.map(docs, & &1["new"]), returning)
  end

  defp replacement_key(key) do
    replacements = %{"1" => "_key", "2" => "_rev", "3" => "_id"}

    case Map.get(replacements, to_string(key)) do
      nil -> key
      k -> k
    end
  end

  defp process_docs(docs, []), do: {length(docs), nil}

  defp process_docs(docs, _returning) do
    # TODO: Possibly broken
    {length(docs), docs}
  end
end
