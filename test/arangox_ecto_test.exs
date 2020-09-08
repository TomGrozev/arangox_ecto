defmodule ArangoXEctoTest do
  use ExUnit.Case
  @moduletag :supported

  doctest ArangoXEcto

  alias ArangoXEctoTest.Integration.{User, Post}
  alias ArangoXEctoTest.Repo

  test "create relations" do
    user = %User{first_name: "a", last_name: "b"} |> Repo.insert!()
#    post = Ecto.build_assoc(user, :wrote_post, %{title: "test", text: "abc"}) |> Repo.insert!()

#    IO.inspect(user)
#    IO.inspect(post)
#    IO.inspect(Repo.get(User, user.id) |> Repo.preload(:wrote_post))

    assert true
  end
end
