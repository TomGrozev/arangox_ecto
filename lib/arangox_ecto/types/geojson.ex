defmodule ArangoXEcto.Types.GeoJSON do
  @moduledoc """
  Defines a GeoJSON type for use in ecto schemas

  This will handle conversion of a Geo struct into a map for storage in the database.

  Use as the type of a field in an Ecto schema. For example:

      schema "users" do
        field :location, ArangoXEcto.Types.GeoJSON
      end
  """
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  @spec cast(Geo.geometry()) :: {:ok, map()} | :error
  def cast(geodata) when is_map(geodata),
    do: Geo.JSON.encode(geodata)

  def cast(geodata) when is_binary(geodata),
    do: Geo.WKT.encode(geodata)

  def cast(_), do: :error

  @impl true
  @spec load(map()) :: {:ok, Geo.geometry()} | {:error, any()} | :error
  def load(data) when is_map(data) do
    Geo.JSON.decode(data)
  end

  def load(_), do: :error

  @impl true
  @spec dump(map() | Geo.geometry()) :: {:ok, binary()} | {:error, any()} | :error
  def dump(data) when is_struct(data) do
    Geo.JSON.encode(data)
  end

  def dump(data) when is_map(data), do: {:ok, data}

  def dump(_), do: :error
end
