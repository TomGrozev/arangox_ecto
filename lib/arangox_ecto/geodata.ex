defmodule ArangoXEcto.GeoData do
  @moduledoc """
  Methods for interacting with ArangoDB GeoJSON and geo related functions

  The methods within this module are really just helpers to generate `Geo` structs.
  """

  @type coordinate :: number()

  defguard is_coordinate(coordinate) when is_float(coordinate) or is_integer(coordinate)

  defguard is_latitude(coordinate)
           when is_coordinate(coordinate) and coordinate >= -90 and coordinate <= 90

  defguard is_longitude(coordinate)
           when is_coordinate(coordinate) and coordinate >= -180 and coordinate <= 180

  @doc """
  Generates a Geo point
  """
  @spec point(coordinate(), coordinate()) :: Geo.Point.t() | {:error, String.t()}
  def point(lat, lon) do
    %Geo.Point{coordinates: {lon, lat}}
    |> validate()
  end

  @doc """
  Generates a Geo multi point
  """
  @spec multi_point([{coordinate(), coordinate()}]) :: Geo.MultiPoint.t() | {:error, String.t()}
  def multi_point(coords) do
    %Geo.MultiPoint{coordinates: coords}
    |> validate()
  end

  @doc """
  Generates a Geo linestring
  """
  @spec linestring([{coordinate(), coordinate()}]) :: Geo.LineString.t() | {:error, String.t()}
  def linestring(coords) do
    %Geo.LineString{coordinates: coords}
    |> validate()
  end

  @doc """
  Generates a Geo multi linestring
  """
  @spec multi_linestring([[{coordinate(), coordinate()}]]) ::
          Geo.MultiLineString.t() | {:error, any()}
  def multi_linestring(coords) do
    %Geo.MultiLineString{coordinates: coords}
    |> validate()
  end

  @doc """
  Generates a Geo polygon
  """
  @spec polygon([[{coordinate(), coordinate()}]]) :: Geo.Polygon.t() | {:error, String.t()}
  def polygon(coords) do
    %Geo.Polygon{coordinates: maybe_embed_in_list(coords)}
    |> validate()
  end

  @doc """
  Generates a Geo multi polygon
  """
  @spec multi_polygon([[[{coordinate(), coordinate()}]]]) ::
          Geo.MultiPolygon.t() | {:error, String.t()}
  def multi_polygon(coords) do
    %Geo.MultiPolygon{coordinates: maybe_embed_in_list(coords)}
    |> validate()
  end

  @doc """
  Sanitizes coordinates to ensure they are valid

  This function is not automatically applied to Geo constructors and must be applied before hand
  """
  @spec sanitize(list() | {coordinate(), coordinate()}) :: list() | {coordinate(), coordinate()}
  def sanitize({lat, lon} = coords) when is_latitude(lat) and is_longitude(lon), do: coords

  def sanitize({lat, lon}) when lat < -90, do: {lat + 180, lon} |> sanitize()
  def sanitize({lat, lon}) when lat > 90, do: {lat - 180, lon} |> sanitize()
  def sanitize({lat, lon}) when lon < -180, do: {lat, lon + 360} |> sanitize()
  def sanitize({lat, lon}) when lon > 180, do: {lat, lon - 360} |> sanitize()

  def sanitize(coord_list) when is_list(coord_list),
    do: Enum.map(coord_list, &sanitize/1)

  defp maybe_embed_in_list([{_, _} | _] = coords), do: [coords]

  defp maybe_embed_in_list(coords), do: coords

  @doc """
  Validates the coordinates of a Geo struct
  """
  @spec validate(geo :: Geo.geometry()) :: Geo.geometry() | {:error, String.t()}
  def validate(%{coordinates: coords} = geo) do
    case validate_coords(coords) do
      {:error, reason} ->
        {:error, reason}

      new_coords ->
        Map.put(geo, :coordinates, new_coords)
    end
  end

  defp validate_coords(coords) when is_list(coords) do
    Enum.reduce_while(coords, [], fn coord, acc ->
      case validate_coords(coord) do
        {:error, reason} -> {:halt, {:error, reason}}
        item -> {:cont, [item | acc]}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      items -> Enum.reverse(items)
    end
  end

  defp validate_coords({lon, lat}) do
    with {:ok, lon} <- parse_coord(lon),
         {:ok, lat} <- parse_coord(lat) do
      cond do
        not is_longitude(lon) ->
          {:error, "longitude is invalid"}

        not is_latitude(lat) ->
          {:error, "latitude is invalid"}

        true ->
          {lon, lat}
      end
    end
  end

  defp validate_coords(_), do: {:error, "invalid coordinates tuple"}

  defp parse_coord(coord) when is_binary(coord) do
    case Float.parse(coord) do
      :error -> {:error, "coordinate must be a number"}
      {float, _} -> {:ok, float}
    end
  end

  defp parse_coord(coord) when is_integer(coord), do: {:ok, coord / 1.0}
  defp parse_coord(coord) when is_float(coord), do: {:ok, coord}
  defp parse_coord(coord), do: {:error, "invalid coordinate type #{inspect(coord)}"}
end
