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

  import ArangoXEcto.GeoData, only: [validate: 1]

  @impl true
  def type, do: :map

  @impl true
  @spec cast(Geo.geometry() | map()) :: {:ok, map()} | :error
  def cast(geodata) when is_struct(geodata) do
    with %{} = geo <- validate(geodata) do
      geo
      |> Geo.JSON.encode()
    end
    |> process_error()
  end

  def cast(geodata) when is_map(geodata) do
    with {:ok, geo} <- Geo.JSON.decode(geodata) do
      cast(geo)
    end
    |> process_error()
  end

  def cast(_), do: :error

  @impl true
  @spec load(map()) :: {:ok, Geo.geometry()} | {:error, any()} | :error
  def load(data) when is_map(data) do
    data
    |> Geo.JSON.decode()
    |> process_error()
  end

  def load(_), do: :error

  @impl true
  @spec dump(map() | Geo.geometry()) :: {:ok, binary()} | {:error, any()} | :error
  def dump(data) when is_struct(data) do
    data
    |> Geo.JSON.encode()
    |> process_error()
  end

  def dump(_), do: :error

  defp process_error({:error, %{message: nil}}), do: {:error, [message: "unknown error"]}

  defp process_error({:error, %{message: message}}), do: {:error, [message: message]}
  defp process_error({:error, message}) when is_binary(message), do: {:error, [message: message]}

  defp process_error(any), do: any
end
