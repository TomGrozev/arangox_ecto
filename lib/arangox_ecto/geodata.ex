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
  @spec point(coordinate(), coordinate()) :: Geo.Point.t()
  def point(lat, lon) when is_latitude(lat) and is_longitude(lon),
    do: %Geo.Point{coordinates: {lon, lat}}

  def point(_, _), do: raise(ArgumentError, "Invalid coordinates provided")

  @doc """
  Generates a Geo multi point
  """
  @spec multi_point([{coordinate(), coordinate()}]) :: Geo.MultiPoint.t()
  def multi_point(coords),
    do: %Geo.MultiPoint{coordinates: filter_coordinates(coords)}

  @doc """
  Generates a Geo linestring
  """
  @spec linestring([{coordinate(), coordinate()}]) :: Geo.LineString.t()
  def linestring(coords),
    do: %Geo.LineString{coordinates: filter_valid_coordinates(coords)}

  @doc """
  Generates a Geo multi linestring
  """
  @spec multi_linestring([[{coordinate(), coordinate()}]]) :: Geo.MultiLineString.t()
  def multi_linestring(coords),
    do: %Geo.MultiLineString{coordinates: filter_coordinates(coords)}

  @doc """
  Generates a Geo polygon
  """
  @spec polygon([[{coordinate(), coordinate()}]]) :: Geo.Polygon.t()
  def polygon(coords),
    do: %Geo.Polygon{coordinates: filter_coordinates(coords)}

  @doc """
  Generates a Geo multi polygon
  """
  @spec multi_polygon([[[{coordinate(), coordinate()}]]]) :: Geo.MultiPolygon.t()
  def multi_polygon(coords),
    do: %Geo.MultiPolygon{coordinates: filter_coordinates(coords)}

  @spec filter_coordinates(list()) :: list()
  def filter_coordinates(coords_list) do
    coords_list
    |> Enum.map(&filter_valid_coordinates/1)
  end

  defp filter_valid_coordinates({lat, lon}) when is_latitude(lat) and is_longitude(lon),
    do: {lon, lat}

  defp filter_valid_coordinates({lat, lon}),
    do: raise(ArgumentError, "Invalid coordinates provided: {#{lat}, #{lon}}")

  defp filter_valid_coordinates(coords) when is_tuple(coords),
    do: raise(ArgumentError, "Invalid number of coordinate tuple")

  defp filter_valid_coordinates([h | t]),
    do: [filter_valid_coordinates(h) | filter_valid_coordinates(t)]

  defp filter_valid_coordinates([]), do: []
end
