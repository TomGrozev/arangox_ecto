defmodule ArangoXEctoTest.Types.GeojsonTest do
  use ExUnit.Case

  alias ArangoXEcto.Types.GeoJSON

  describe "cast/1" do
    test "it can convert a point to a map" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.cast(location) ==
               {:ok, %{"type" => "Point", "coordinates" => [100.0, 0.0]}}
    end

    test "it can convert a polygon to a map" do
      polygon = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {99.0, 0.0}, {98.0, 1.0}]]}

      assert GeoJSON.cast(polygon) ==
               {:ok,
                %{
                  "type" => "Polygon",
                  "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
                }}
    end

    test "fails on non map casting" do
      assert :error = GeoJSON.cast("POINT(100.0,0.0)")
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

    test "fails on non map loading" do
      assert :error = GeoJSON.load("POINT(100.0,0.0)")
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

    test "fails on non geo data dumping" do
      assert :error = GeoJSON.dump("POINT(100.0,0.0)")
    end
  end
end
