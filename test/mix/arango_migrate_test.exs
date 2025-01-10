defmodule ArangoXEcto.Mix.ArangoMigrate do
  use ExUnit.Case
  @moduletag :mix

  alias Mix.Tasks.Arango.{Migrate, Rollback}

  test "generates default path" do
    assert_raise Mix.Error, ~r"Could not find migrations directory", fn ->
      Migrate.run([
        "-r",
        "ArangoXEcto.Integration.TestRepo"
      ])
    end
  end

  test "create and rollback migration" do
    assert :ok =
             Migrate.run([
               "-r",
               "ArangoXEcto.Integration.TestRepo",
               "--migrations-path",
               "test/support/migration_test"
             ])

    assert :ok =
             Rollback.run([
               "-r",
               "ArangoXEcto.Integration.TestRepo",
               "--migrations-path",
               "test/support/migration_test"
             ])
  end
end
