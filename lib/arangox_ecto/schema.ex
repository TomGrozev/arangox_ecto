defmodule ArangoXEcto.Schema do
  @moduledoc """
  This module is a helper to automatically specify the primary key.

  The primary key is the Arango `_key` field but the _id field is also provided.

  Schema modules should use this module by add `use ArangoXEcto.Schema` to the module. The only
  exception to this is if the collection is an edge collection, in that case refer to ArangoXEcto.Edge.

  ## Example

      defmodule MyProject.Accounts.User do
        use ArangoXEcto.Schema
        import Ecto.Changeset

        schema "users" do
          field :first_name, :string
          field :last_name, :string

          timestamps()
        end

        @doc false
        def changeset(app, attrs) do
          app
          |> cast(attrs, [:first_name, :last_name])
          |> validate_required([:first_name, :last_name])
        end
      end
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import unquote(__MODULE__)

      @primary_key {:id, :binary_id, autogenerate: true, source: :_key}
      @foreign_key_type :binary_id
    end
  end
end
