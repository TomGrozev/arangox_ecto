defmodule ArangoXEcto.View.Metadata do
  @moduledoc """
  Stores metadata of a struct.

  ## State

  The state of the view is stored in the `:state` field and allows
  following values:

    * `:built` - the struct was constructed in memory and is not persisted
      to database yet;
    * `:loaded` - the struct was loaded from database and represents
      persisted data;
    * `:deleted` - the struct was deleted and no longer represents persisted
      data.

  ## Source

  The `:source` tracks the view where the struct is or should
  be persisted to.

  ## View

  The `:view` field refers the module name for the view this metadata belongs to.
  """

  defstruct [:state, :name, :view]

  @type state :: :built | :loaded | :deleted

  @type t(view) :: %__MODULE__{
          state: state(),
          name: ArangoXEcto.View.name(),
          view: view
        }

  @type t :: t(module)

  defimpl Inspect do
    @moduledoc """
    Implements Inspect for the Metadata module
    """

    import Inspect.Algebra

    def inspect(metadata, opts) do
      %{name: name, state: state} = metadata

      entries =
        for entry <- [state, name],
            entry != nil,
            do: to_doc(entry, opts)

      concat(["#ArangoXEcto.View.Metadata<"] ++ Enum.intersperse(entries, ", ") ++ [">"])
    end
  end
end
