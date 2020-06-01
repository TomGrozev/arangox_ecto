defmodule EctoArangodbTest do
  use ExUnit.Case
  doctest Ecto.Adapters.ArangoDB

  import Ecto.Query

  alias EctoArangodbTest.Test

  describe "create query in AQL" do
    test "query selecting singular document" do
      assert get_aql_query(from u in Test) =~ "FOR t0 IN `test` RETURN [ t0.`_key`, t0.`title`, t0.`inserted_at`, t0.`updated_at` ]"
    end
  end

  defp get_aql_query(query, operation \\ :all) do
    apply(Ecto.Adapters.ArangoDB.Query, operation, [query])
  end
end
