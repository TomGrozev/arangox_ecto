defmodule ArangoXEcto.Schema do
  @moduledoc """
  This module is a helper to automatically specify the primary key.

  The primary key is the Arango `_key` field but the _id field is also provided.
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import unquote(__MODULE__)

      @primary_key {:id, :binary_id, autogenerate: true, source: :_key}
      @foreign_key_type :binary_id
    end
  end

  @doc """
  Describes an outgoing relationship for current `ArangoXEcto.Schema` to another `ArangoXEcto.Schema`


  """
  defmacro outgoing_rel(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      if Keyword.get(opts, :unique, false) do
        has_one(unquote(name), unquote(target),
          foreign_key: unquote(name) |> build_foreign_key(),
          on_replace: :delete
        )
      else
        has_many(unquote(name), unquote(target),
          foreign_key: unquote(name) |> build_foreign_key(),
          on_replace: :delete
        )
      end
    end
  end

  @doc """
  Describes an incoming relationship for current `ArangoXEcto.Schema` to another `ArangoXEcto.Schema`


  """
  defmacro incoming_rel(name, target, _opts \\ []) do
    quote do
      belongs_to(unquote(name), unquote(target),
        foreign_key: unquote(name) |> build_foreign_key(),
        on_replace: :delete
      )
    end
  end

  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_rel")
    |> String.to_atom()
  end
end
