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

    test "it can take a json map" do
      location = %{
        "coordinates" => [100.0, 1.0],
        "type" => "Point",
        "properties" => %{"address" => "123 Fake St"}
      }

      assert {:ok,
              %{
                "coordinates" => [100.0, 1.0],
                "properties" => %{"address" => "123 Fake St"},
                "type" => "Point"
              }} =
               GeoJSON.cast(location)
    end

    test "it can convert a string coords" do
      location = %{
        "coordinates" => ["100.0", "1.0"],
        "type" => "Point",
        "properties" => %{"address" => "123 Fake St"}
      }

      assert {:ok,
              %{
                "coordinates" => [100.0, 1.0],
                "properties" => %{"address" => "123 Fake St"},
                "type" => "Point"
              }} =
               GeoJSON.cast(location)
    end

    test "fails on non map casting" do
      assert :error = GeoJSON.cast("POINT(100.0,0.0)")
    end

    test "fails with invalid coords" do
      location = %Geo.Point{coordinates: {1.0, 100}}

      assert {:error, [{:message, "latitude is invalid"}]} = GeoJSON.cast(location)
    end

    test "fails with message on map type" do
      location = %{coordinates: {100.0, 0.0}}

      assert {:error, [{:message, "unknown error"}]} = GeoJSON.cast(location)
    end

    test "fails with message on wrong type for map" do
      location = %{
        "coordinates" => [100.0, 0.0],
        "type" => "something fake",
        "properties" => %{"address" => "123 Fake St"}
      }

      assert {:error, [{:message, "something fake is not a valid type"}]} = GeoJSON.cast(location)
    end

    test "fails with invalid coords type" do
      location = %{
        "coordinates" => [:lon, :lat],
        "type" => "Point",
        "properties" => %{"address" => "123 Fake St"}
      }

      location2 = %{
        "coordinates" => ["lon", "lat"],
        "type" => "Point",
        "properties" => %{"address" => "123 Fake St"}
      }

      assert {:error, [{:message, "invalid coordinate type :lon"}]} = GeoJSON.cast(location)

      assert {:error, [{:message, "coordinate must be a number"}]} = GeoJSON.cast(location2)
    end
  end

  describe "load/1" do
    test "it can load a point" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert {:ok, ^location} = GeoJSON.load(%{"type" => "Point", "coordinates" => [100.0, 0.0]})
    end

    test "it can load a polygon" do
      polygon = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {99.0, 0.0}, {98.0, 1.0}]]}

      assert {:ok, ^polygon} =
               GeoJSON.load(%{
                 "type" => "Polygon",
                 "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
               })
    end

    test "fails on non map loading" do
      assert :error = GeoJSON.load("POINT(100.0,0.0)")
    end

    test "fails with message on map type" do
      assert {:error, [{:message, "not real is not a valid type"}]} =
               GeoJSON.load(%{
                 "type" => "not real",
                 "coordinates" => [[[100.0, 0.0], [99.0, 0.0], [98.0, 1.0]]]
               })
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
