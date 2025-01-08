defmodule ArangoXEcto.MigrationTest.MigrationsForTest do
  use ArangoXEcto.Migration

  def change do
    create collection(:test_collection) do
      add :text, :string
    end
  end
end
