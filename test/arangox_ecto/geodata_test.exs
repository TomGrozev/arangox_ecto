defmodule ArangoXEctoTest.GeodataTest do
  use ExUnit.Case
  @moduletag :supported

  describe "point/2" do
    test "it takes valid coordinates" do
      correct = %Geo.Point{coordinates: {100.0, 0.0}}

      assert ArangoXEcto.GeoData.point(0, 100) == correct
    end

    test "it does not accept out of bounds coordinates" do
      # Lat is out of bounds
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.point(100, 0)
      end
    end
  end

  describe "multi_point/1" do
    test "it takes valid coordinates" do
      coords = [{0, 100}, {9, 10}]
      correct = %Geo.MultiPoint{coordinates: [{100.0, 0.0}, {10.0, 9.0}]}

      assert ArangoXEcto.GeoData.multi_point(coords) == correct
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.multi_point([{100, 0}, {10, 9}])
      end
    end

    test "it fails for invalid single element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_point([{0, 100}, {10}])
      end
    end

    test "it fails for invalid three or more element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_point([{0, 100}, {10, 0, 1}])
      end
    end

    #    test "it converts a single point into a Geo.Point" do
    #      assert ArangoXEcto.GeoData.multi_point([{0, 100}]) == %Geo.Point{coordinates: {100.0, 0.0}}
    #    end
  end

  describe "linestring/1" do
    test "it takes valid coordinates" do
      coords = [{0, 100}, {9, 10}]
      correct = %Geo.LineString{coordinates: [{100.0, 0.0}, {10.0, 9.0}]}

      assert ArangoXEcto.GeoData.linestring(coords) == correct
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.linestring([{100, 0}, {10, 9}])
      end
    end

    test "it fails for invalid single element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.linestring([{0, 100}, {10}])
      end
    end

    test "it fails for invalid three or more element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.linestring([{0, 100}, {10, 0, 1}])
      end
    end

    #    test "it converts a single point into a Geo.Point" do
    #      assert ArangoXEcto.GeoData.linestring([{0, 100}]) == %Geo.Point{coordinates: {100.0, 0.0}}
    #    end
  end

  describe "multi_linestring/1" do
    test "it takes valid coordinates" do
      coords = [[{0, 100}, {9, 10}], [{10, 10}, {20, -20}]]

      correct = %Geo.MultiLineString{
        coordinates: [[{100.0, 0.0}, {10.0, 9.0}], [{10, 10}, {-20, 20}]]
      }

      assert ArangoXEcto.GeoData.multi_linestring(coords) == correct
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.multi_linestring([[{100, 0}, {10, 9}]])
      end
    end

    test "it fails for invalid single element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_linestring([[{0, 100}, {10}]])
      end
    end

    test "it fails for invalid three or more element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_linestring([[{0, 100}, {10, 0, 1}]])
      end
    end

    ##    test "it converts a single array of points to a Geo.LineString" do
    ##      assert ArangoXEcto.GeoData.multi_linestring([[{0, 100}, {10, 9}]]) == %Geo.LineString{
    ##               coordinates: [{100.0, 0.0}, {9.0, 10.0}]
    ##             }
    ##    end
    ##
    ##    test "it converts a single single point into a Geo.Point" do
    ##      assert ArangoXEcto.GeoData.multi_linestring([[{0, 100}]]) == %Geo.Point{
    ##               coordinates: {100.0, 0.0}
    ##             }
    ##    end
  end

  describe "polygon/1" do
    test "it takes valid simple polygon" do
      coords = [{0, 100}, {9, 10}]
      correct = %Geo.Polygon{coordinates: [{100.0, 0.0}, {10.0, 9.0}]}

      assert ArangoXEcto.GeoData.polygon(coords) == correct
    end

    test "it takes valid advanced polygon" do
      coords = [[{0, 100}, {9, 10}], [{10, 10}, {20, -20}]]
      correct = %Geo.Polygon{coordinates: [[{100.0, 0.0}, {10.0, 9.0}], [{10, 10}, {-20, 20}]]}

      assert ArangoXEcto.GeoData.polygon(coords) == correct
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.polygon([{100, 0}, {10, 9}])
      end
    end

    test "it fails for invalid single element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.polygon([{0, 100}, {10}])
      end
    end

    test "it fails for invalid three or more element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.polygon([{0, 100}, {10, 0, 1}])
      end
    end

    #    test "it converts a single single point simple polygon into a Geo.Point" do
    #      assert ArangoXEcto.GeoData.polygon([{0, 100}]) == %Geo.Point{coordinates: {100.0, 0.0}}
    #    end
    #
    #    test "it converts a single single point advanced polygon into a Geo.Point" do
    #      assert ArangoXEcto.GeoData.polygon([[{0, 100}]]) == %Geo.Point{coordinates: {100.0, 0.0}}
    #    end
    #
    #    test "it converts a two point polygon into a Geo.LineString" do
    #      assert ArangoXEcto.GeoData.polygon([{0, 100}, {10, 9}]) == %Geo.LineString{
    #               coordinates: [{100.0, 0.0}, {9, 10}]
    #             }
    #    end
  end

  describe "multi_polygon/1" do
    test "it takes valid multi polygons" do
      coords = [
        [[{0, 100}, {9, 10}], [{10, 10}, {20, -20}]],
        [[{0, 100}, {9, 10}], [{10, 10}, {20, -20}]]
      ]

      correct = %Geo.MultiPolygon{
        coordinates: [
          [[{100.0, 0.0}, {10.0, 9.0}], [{10, 10}, {-20, 20}]],
          [[{100.0, 0.0}, {10.0, 9.0}], [{10, 10}, {-20, 20}]]
        ]
      }

      assert ArangoXEcto.GeoData.multi_polygon(coords) == correct
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert_raise ArgumentError, ~r/Invalid coordinates provided/, fn ->
        ArangoXEcto.GeoData.multi_polygon([[{100, 0}, {10, 9}]])
      end
    end

    test "it fails for invalid single element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_polygon([[{0, 100}, {10}]])
      end
    end

    test "it fails for invalid three or more element tuples" do
      assert_raise ArgumentError, ~r/Invalid number of coordinate tuple/, fn ->
        ArangoXEcto.GeoData.multi_polygon([[{0, 100}, {10, 0, 1}]])
      end
    end

    # test "it converts a single point polygon into a Geo.Point" do
    #  assert ArangoXEcto.GeoData.multi_polygon([[{0, 100}]]) == %Geo.Point{
    #           coordinates: {100.0, 0.0}
    #         }
    # end

    # test "it converts a two point polygon into a Geo.LineString" do
    #  assert ArangoXEcto.GeoData.multi_polygon([{0, 100}, {10, 9}]) == %Geo.LineString{
    #           coordinates: [{100.0, 0.0}, {9, 10}]
    #         }
    # end

    # test "it converts a single polygon into a Geo.Polygon" do
    #  assert ArangoXEcto.GeoData.multi_polygon([{0, 100}, {10, 9}, {50, 50}]) == %Geo.Polygon{
    #           coordinates: [{100.0, 0.0}, {9, 10}, {50, 50}]
    #         }
    # end
  end
end
