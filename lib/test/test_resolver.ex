defmodule Test.Resolver do
  alias Test.{Repo, Test}

  def test do
    {:ok, _} = Ecto.Adapters.ArangoDB.ensure_all_started(:ecto_arangodb, :temporary)

    objs = [%{title: "Test321"}, %{title: "hihihi"}]
    #    Repo.insert_all(Test, objs)

    #    Repo.all(Test)
    test = Repo.get(Test, "385891")
    IO.inspect(test)
#    test = Test.changeset(test, %{title: "HHHHHHHHHHHHHHH"})
#
#    IO.inspect(Repo.update_all(Test, set: [title: "abc321"]))
  end
end
