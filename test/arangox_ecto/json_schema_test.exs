defmodule ArangoxEcto.JsonSchemaTest do
  use ExUnit.Case

  alias ArangoXEcto.Migration.JsonSchema

  describe "convert/2" do
    test "create with schema" do
      schema =
        JsonSchema.convert(
          [
            {:modify, :first_name, :string, []},
            {:add, :gender, :enum, values: [:male, :female]},
            {:add, :type, :const, value: :user},
            {:add, :pets, {:array, :string}, []},
            {:remove, :last_name},
            {:remove, :age, :integer, []},
            {:rename, :persons, :people},
            {:modify, :levels,
             [
               {:modify, :name, :string, []}
             ], []}
          ],
          schema: %{
            "rule" => %{
              "properties" => %{
                "first_name" => %{"type" => "integer"},
                "last_name" => %{"type" => "string"},
                "age" => %{"type" => "integer"},
                "persons" => %{"type" => "string"},
                "levels" => %{
                  "type" => "object",
                  "properties" => %{
                    "name" => %{"type" => "integer"}
                  }
                }
              }
            }
          }
        )

      assert %{
               properties: %{
                 type: %{const: :user, type: ["string", "null"]},
                 levels: %{
                   type: ["object", "null"],
                   properties: %{name: %{type: ["string", "null"]}}
                 },
                 first_name: %{type: ["string", "null"]},
                 gender: %{type: ["string", "null"], enum: [:male, :female]},
                 pets: %{type: ["array", "null"], items: %{type: ["string", "null"]}},
                 people: %{type: "string"}
               }
             } = schema
    end
  end
end
