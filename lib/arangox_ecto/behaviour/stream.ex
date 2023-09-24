defmodule ArangoXEcto.Behaviour.Stream do
  @moduledoc false
  defstruct [:meta, :statement, :params, :opts]

  @type t :: %__MODULE__{}

  @doc false
  @spec build(meta :: map(), statement :: String.t(), params :: map(), opts :: Keyword.t()) :: t()
  def build(meta, statement, params, opts) do
    %__MODULE__{meta: meta, statement: statement, params: params, opts: opts}
  end
end

alias ArangoXEcto.Behaviour.Stream

defimpl Enumerable, for: Stream do
  @moduledoc false

  @doc false
  def count(_), do: {:error, __MODULE__}
  @doc false
  def member?(_, _), do: {:error, __MODULE__}
  @doc false
  def slice(_), do: {:error, __MODULE__}

  @doc false
  def reduce(stream, acc, func) do
    %Stream{meta: meta, statement: statement, params: params, opts: opts} = stream
    ArangoXEcto.Adapter.reduce(meta, statement, params, opts, acc, func)
  end
end

defimpl Collectable, for: Stream do
  @moduledoc false

  @doc false
  def into(stream) do
    %Stream{meta: meta, statement: statement, params: params, opts: opts} = stream
    {state, fun} = ArangoXEcto.Adapter.into(meta, statement, params, opts)
    {state, make_into(fun, stream)}
  end

  defp make_into(fun, stream) do
    fn
      state, :done ->
        fun.(state, :done)
        stream

      state, acc ->
        fun.(state, acc)
    end
  end
end
