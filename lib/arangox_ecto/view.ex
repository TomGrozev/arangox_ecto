defmodule ArangoXEcto.View do
  @moduledoc """
  ArangoSearch view module

  A bunch of functions to help create and manage Arango Search views.

  A lot of credit goes to the `Ecto.Schema` module for inspiration of structure.

  ## Example

    defmodule Something.UserSearch do
      use ArangoXEcto.View

      alias ArangoXEcto.View.Link

      view "user_search" do
        primary_sort [
          %{field: :created_at, direction: :asc}
        ]

        stored_values [
          %{fields: [:name], compression: :lz4}
        ]

        links %{
          MyApp.Users: %Link{
            includeAllFields: true,
            fields: %{
              name: %Link{
                analyzers: [:text_en]
              }
            }
          }
        }

        options  [
          primarySortCompression: :lz4
        ]
      end
    end
  """

  # alias ArangoXEcto.View.{Link, Metadata}
  alias ArangoXEcto.View.Link

  @type name :: String.t()
  @type compression :: :lz4 | :none
  # @type t :: %__MODULE__{
  #         name: String.t(),
  #         primarySort: [%{field: atom(), direction: :asc | :desc}],
  #         primarySortCompression: compression(),
  #         storedValues: [%{fields: list(String.t()), compression: compression()}],
  #         links: %{Ecto.Schema.t() => ArangoXEcto.View.Link.t()},
  #         writebufferIdle: integer(),
  #         writebufferIdle: integer(),
  #         writebufferSizeMax: integer(),
  #         commitIntervalMsec: integer(),
  #         cleanupIntervalStep: integer(),
  #         consolidationIntervalMsec: integer(),
  #         consolidationPolicy:
  #           %{
  #             type: :tier,
  #             segmentsMin: integer(),
  #             segmentsMax: integer(),
  #             segmentsBytesMax: integer(),
  #             segmentsBytesFloor: integer(),
  #             minScore: integer()
  #           }
  #           | %{type: :bytes_accum, threshold: float()}
  #       }

  @doc false
  defmacro __using__(_) do
    quote do
      import ArangoXEcto.View, only: [view: 2]
    end
  end

  @doc """
  Defines a view
  """
  defmacro view(name, do: block) do
    view(__CALLER__, name, true, block)
  end

  defp view(caller, name, meta?, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :arango_view_defined) do
          raise "view schema already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        @view_name unquote(name)

        @arango_view_defined unquote(caller.line)

        meta? = unquote(meta?)

        if meta? do
          unless is_binary(@view_name) do
            raise ArgumentError, "view name must be a string, got: #{inspect(@view_name)}"
          end

          meta = %ArangoXEcto.View.Metadata{
            state: :built,
            name: @view_name,
            view: __MODULE__
          }
        end

        try do
          import ArangoXEcto.View
          unquote(block)
        after
          :ok
        end
      end

    postlude = set_view_definitions()

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  defp set_view_definitions do
    quote unquote: false do
      def __view__(:name), do: @view_name
      def __view__(:primary_sort), do: @view_primary_sort
      def __view__(:stored_values), do: @view_stored_values
      def __view__(:links), do: @view_links
      def __view__(:options), do: @view_options
    end
  end

  @doc """
  Defines primary sort fields
  """
  defmacro primary_sort(attrs) do
    quote do
      attrs = unquote(attrs)

      unless Enum.all?(attrs, fn
               %{field: field, direction: direction}
               when is_atom(field) and direction in [:asc, :desc] ->
                 true

               _ ->
                 false
             end) do
        raise ArgumentError, "invalid primary sort format"
      end

      @view_primary_sort attrs
    end
  end

  @doc """
  Defines stored value fields
  """
  defmacro stored_values(attrs) do
    quote do
      attrs = unquote(attrs)

      unless Enum.all?(attrs, fn
               %{fields: fields, compression: compression} when compression in [:lz4, :none] ->
                 Enum.all?(fields, &(is_binary(&1) or is_atom(&1)))

               _ ->
                 false
             end) do
        raise ArgumentError, "invalid stored values format"
      end

      @view_stored_values attrs
    end
  end

  @doc """
  Defines link fields
  """
  defmacro links(attrs) do
    quote do
      attrs = unquote(attrs)

      unless Enum.all?(attrs, fn {schema, link} ->
               function_exported?(schema, :__schema__, 1) and Link.valid?(link)
             end) do
        raise ArgumentError, "invalid links format"
      end

      @view_links attrs
    end
  end

  @doc """
  Defines options for view creation
  """
  defmacro options(attrs) do
    quote do
      attrs = unquote(attrs)

      with {:error, invalid_keys} <-
             Keyword.validate(attrs, [
               :consolidationIntervalMsec,
               :consolidationPolicy,
               :commitIntervalMsec,
               :writebufferSizeMax,
               :writebufferIdle,
               :writebufferActive,
               :cleanupIntervalStep,
               :primarySortCompression
             ]) do
        raise ArgumentError, "invalid option keys: #{inspect(invalid_keys)}"
      end

      @view_options attrs
    end
  end

  @doc """
  Generates the view definition
  """
  def definition(view) when is_atom(view) do
    if function_exported?(view, :__view__, 1) do
      %{
        name: view.__view__(:name),
        type: "arangosearch"
      }
      |> maybe_add_to_map(:links, view.__view__(:links) |> process_links())
      |> maybe_add_to_map(:primarySort, view.__view__(:primary_sort))
      |> maybe_add_to_map(:storedValues, view.__view__(:stored_values))
      |> Map.merge(Enum.into(view.__view__(:options), %{}))
    else
      raise ArgumentError, "not a valid view schema"
    end
  end

  defp process_links(links) do
    Enum.reduce(links, %{}, fn {schema, link}, acc ->
      Map.put(acc, schema.__schema__(:source), Link.to_map(link))
    end)
  end

  defp maybe_add_to_map(map, _key, nil), do: map
  defp maybe_add_to_map(map, key, value), do: Map.put(map, key, value)
end
