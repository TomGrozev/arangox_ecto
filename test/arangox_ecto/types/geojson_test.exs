defmodule ArangoXEctoTest.Types.GeojsonTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEcto.Types.GeoJSON

  describe "cast/1" do
    test "it can convert a point to a map" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.cast(%{"type" => "Point", "coordinates" => [100.0, 0.0]}) ==
               {:ok, location}
    end

    test "it can convert a polygon to a map" do
      polygon = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {99.0, 0.0}, {98.0, 1.0}]]}

      assert GeoJSON.cast(%{
               "type" => "Polygon",
               "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
             }) ==
               {:ok, polygon}
    end
  end

  describe "load/1" do
    test "it can load a point" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.load(%{"type" => "Point", "coordinates" => [100.0, 0.0]}) ==
               {:ok, location}
    end

    test "it can load a polygon" do
      polygon = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {99.0, 0.0}, {98.0, 1.0}]]}

      assert GeoJSON.load(%{
               "type" => "Polygon",
               "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
             }) ==
               {:ok, polygon}
    end
  end

  describe "dump/1" do
    test "it can dump a point to a map" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.dump(location) ==
               {:ok, %{"type" => "Point", "coordinates" => [100.0, 0.0]}}
    end

    test "it can dump a polygon to a map" do
      polygon = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {99.0, 0.0}, {98.0, 1.0}]]}

      assert GeoJSON.dump(polygon) ==
               {:ok,
                %{
                  "type" => "Polygon",
                  "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
                }}
    end
  end
end
