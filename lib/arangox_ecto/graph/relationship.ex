defmodule ArangoXEcto.Graph.Relationship do
  @moduledoc """
  Manages relationship operations
  """

  alias Ecto.Adapter.Schema

  @spec create_relationships({:ok, list()}, Arangox.conn(), Ecto.Schema.t(), Schema.fields()) ::
          {:ok, Schema.fields()} | {:invalid, Schema.constraints()}
  def create_relationships({:ok, [_key: key]} = data, conn, schema, fields) do
    schema
    |> do_create_relationships(conn, key, fields)

    data
  end

  defp do_create_relationships(child_schema, conn, to_key, fields) do
    Enum.each(child_schema.__schema__(:associations), fn assoc ->
      data = child_schema.__schema__(:association, assoc)

      if Kernel.match?(%Ecto.Association.BelongsTo{}, data) do
        from =
          with %Ecto.Association.BelongsTo{related: parent_schema, owner_key: key_name} <- data,
               from_source <- parent_schema.__schema__(:source),
               from_key <- Keyword.get(fields, key_name),
               do: "#{from_source}/#{from_key}"

        to =
          with to_source <- child_schema.__schema__(:source),
               do: "#{to_source}/#{to_key}"

        assoc
        |> generate_collection_name()
        |> maybe_create_edges_collection(conn)
        |> insert_relationship(conn, from, to)
      end
    end)
  end

  defp assoc_key(assoc, fields) do
    key =
      "#{assoc}_rel"
      |> String.to_atom()

    Keyword.get(fields, key)
  end

  defp generate_collection_name(assoc), do: "#{assoc}_edges"

  defp maybe_create_edges_collection(collection_name, conn) do
    Arangox.get(conn, "/_api/collection/#{collection_name}")
    |> case do
      {:ok, _request, %Arangox.Response{body: %{"type" => 3, "isSystem" => false}}} ->
        collection_name

      {_status, _any} ->
        create_edges_collection(conn, collection_name)

        collection_name
    end
  end

  defp create_edges_collection(conn, collection_name) do
    Arangox.post!(conn, "/_api/collection", %{name: collection_name, type: 3})
  end

  defp insert_relationship(collection_name, conn, from, to) do
    Arangox.post!(conn, "/_api/document/#{collection_name}", %{_from: from, _to: to})
  end
end
