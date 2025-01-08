defmodule ArangoXEcto.Mix.ArangoGenMigration do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Arango.Gen.Migration

  @migrations_path "/tmp/arangox_ecto_test"

  setup do
    on_exit(fn ->
      File.rm_rf!(@migrations_path)
    end)
  end

  test "create migration" do
    io =
      capture_io(fn ->
        assert :ok =
                 Migration.run([
                   "create_users",
                   "-r",
                   "ArangoXEcto.Integration.TestRepo",
                   "--migrations-path",
                   @migrations_path
                 ])
      end)

    [_, path] = Regex.compile!(".*(#{@migrations_path}/.+\.exs).*") |> Regex.run(io)

    assert File.exists?(path)
  end

  test "failed on no filename" do
    assert_raise Mix.Error,
                 ~r"expected arango.gen.migration to receive the migration file name",
                 fn ->
                   Migration.run([
                     "-r",
                     "ArangoXEcto.Integration.TestRepo",
                     "--migrations-path",
                     @migrations_path
                   ])
                 end
  end

  test "raises on recreation of same name migration" do
    assert :ok =
             Migration.run([
               "create_users",
               "-r",
               "ArangoXEcto.Integration.TestRepo",
               "--migrations-path",
               @migrations_path
             ])

    assert_raise Mix.Error,
                 ~r"Migration can't be created since there is already a migration file with the name",
                 fn ->
                   Migration.run([
                     "create_users",
                     "-r",
                     "ArangoXEcto.Integration.TestRepo",
                     "--migrations-path",
                     @migrations_path
                   ])
                 end
  end
end
