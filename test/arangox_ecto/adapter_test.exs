defmodule ArangoXEctoTest.AdapterTest do
  use ExUnit.Case
  @moduletag :supported

  alias ArangoXEctoTest.Integration.User
  alias ArangoXEctoTest.Repo

  describe "geojson type" do
    test "valid geojson struct" do
      location = %Geo.Point{coordinates: {100.0, 0.0}, srid: nil}

      {:ok, %User{location: loaded_location}} =
        %User{location: location}
        |> Repo.insert()

      assert loaded_location == location
    end
  end

  describe "enum type" do
    test "custom type is loaded and dumped correctly" do
      assert {:ok, %User{gender: :other}} = Repo.insert(%User{gender: :other})
    end
  end
end
