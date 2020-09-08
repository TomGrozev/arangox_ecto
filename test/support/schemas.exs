defmodule ArangoXEctoTest.Integration.User do
  use ArangoXEcto.Schema

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
  end
end

defmodule ArangoXEctoTest.Integration.Post do
  use ArangoXEcto.Schema

  schema "posts" do
    field(:title, :string)
    field(:text, :string)
  end
end
