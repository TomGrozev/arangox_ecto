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
      assert {:error, "latitude is invalid"} = ArangoXEcto.GeoData.point(100, 0)
    end
  end

  describe "multi_point/1" do
    test "it takes valid coordinates" do
      coords = [{3, 70}, {10, 9}]

      assert %Geo.MultiPoint{coordinates: [{3.0, 70.0}, {10.0, 9.0}]} =
               ArangoXEcto.GeoData.multi_point(coords)
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert {:error, "latitude is invalid"} =
               ArangoXEcto.GeoData.multi_point([{100, 200}, {10, 9}])
    end

    test "it fails for invalid single element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_point([{0, 50}, {10}])
    end

    test "it fails for invalid three or more element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_point([{0, 50}, {10, 0, 1}])
    end
  end

  describe "linestring/1" do
    test "it takes valid coordinates" do
      coords = [{1, 30}, {9, 10}]

      assert %Geo.LineString{coordinates: [{1.0, 30.0}, {9.0, 10.0}]} =
               ArangoXEcto.GeoData.linestring(coords)
    end

    test "it does not accept out of bounds coords" do
      # Lon is out of bound
      assert {:error, "longitude is invalid"} =
               ArangoXEcto.GeoData.linestring([{200, 0}, {10, 9}])
    end

    test "it fails for invalid single element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.linestring([{0, 50}, {10}])
    end

    test "it fails for invalid three or more element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.linestring([{0, 50}, {10, 0, 1}])
    end
  end

  describe "multi_linestring/1" do
    test "it takes valid coordinates" do
      coords = [[{8, 50}, {9, 10}], [{10, 10}, {20, -20}]]

      assert %Geo.MultiLineString{
               coordinates: [[{8.0, 50.0}, {9.0, 10.0}], [{10.0, 10.0}, {20.0, -20.0}]]
             } = ArangoXEcto.GeoData.multi_linestring(coords)
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert {:error, "latitude is invalid"} =
               ArangoXEcto.GeoData.multi_linestring([[{100, 200}, {10, 9}]])
    end

    test "it fails for invalid single element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_linestring([[{0, 50}, {10}]])
    end

    test "it fails for invalid three or more element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_linestring([[{0, 50}, {10, 0, 1}]])
    end
  end

  describe "polygon/1" do
    test "it takes valid simple polygon" do
      coords = [{9, 90}, {9, 10}]

      assert %Geo.Polygon{coordinates: [[{9.0, 90.0}, {9.0, 10.0}]]} =
               ArangoXEcto.GeoData.polygon(coords)
    end

    test "it takes valid advanced polygon" do
      coords = [[{2, 20}, {9, 10}], [{10, 10}, {20, -20}]]

      assert %Geo.Polygon{
               coordinates: [[{2.0, 20.0}, {9.0, 10.0}], [{10.0, 10.0}, {20.0, -20.0}]]
             } =
               ArangoXEcto.GeoData.polygon(coords)
    end

    test "it does not accept out of bounds coords" do
      # Lon is out of bound
      assert {:error, "longitude is invalid"} =
               ArangoXEcto.GeoData.polygon([{200, 0}, {10, 9}])
    end

    test "it fails for invalid single element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.polygon([{0, 50}, {10}])
    end

    test "it fails for invalid three or more element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.polygon([{0, 50}, {10, 0, 1}])
    end
  end

  describe "multi_polygon/1" do
    test "it takes valid multi polygons" do
      coords = [
        [[{2, 90}, {9, 10}], [{10, 10}, {20, -20}]],
        [[{3, 90}, {9, 10}], [{10, 10}, {20, -20}]]
      ]

      assert %Geo.MultiPolygon{
               coordinates: [
                 [[{2.0, 90.0}, {9.0, 10.0}], [{10.0, 10.0}, {20.0, -20.0}]],
                 [[{3.0, 90.0}, {9.0, 10.0}], [{10.0, 10.0}, {20.0, -20.0}]]
               ]
             } =
               ArangoXEcto.GeoData.multi_polygon(coords)
    end

    test "it does not accept out of bounds coords" do
      # Lat is out of bound
      assert {:error, "latitude is invalid"} =
               ArangoXEcto.GeoData.multi_polygon([[{100, 200}, {10, 9}]])
    end

    test "it fails for invalid single element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_polygon([[{0, 50}, {10}]])
    end

    test "it fails for invalid three or more element tuples" do
      assert {:error, "invalid coordinates tuple"} =
               ArangoXEcto.GeoData.multi_polygon([[{0, 50}, {10, 0, 1}]])
    end
  end

  describe "sanitize/1" do
    test "it converts out of bounds latitude to inbounds" do
      assert ArangoXEcto.GeoData.sanitize({-91.0, 90.0}) == {89.0, 90.0}
    end

    test "it converts out of bounds longitude to inbounds" do
      assert ArangoXEcto.GeoData.sanitize({-15.294722, 181.731667}) == {-15.294722, -178.268333}
    end
  end
end
