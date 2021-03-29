defmodule ArangoXEctoTest.Types.GeojsonTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEcto.Types.GeoJSON

  describe "cast/1" do
    test "it can convert to a map" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.load(%{"type" => "Point", "coordinates" => [100.0, 0.0]}) ==
               {:ok, location}
    end
  end

  describe "load/1" do
    test "it can load a type" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.load(%{"type" => "Point", "coordinates" => [100.0, 0.0]}) ==
               {:ok, location}
    end
  end

  describe "dump/1" do
    test "it can dump a type to a map" do
      location = %Geo.Point{coordinates: {100.0, 0.0}}

      assert GeoJSON.dump(location) ==
               {:ok, %{"type" => "Point", "coordinates" => [100.0, 0.0]}}
    end
  end
end
