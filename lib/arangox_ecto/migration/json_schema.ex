defmodule ArangoXEcto.Migration.JsonSchema do
  @moduledoc """
  Converts migration command to JSON Schema
  """

  @type level :: :none | :new | :moderate | :strict

  @type t :: %{rule: map(), level: level(), message: String.t()}

  @available_levels [:none, :new, :moderate, :strict]

  @default_msg "The document does not match the schema. Please ensure the document matches the json schema."

  @doc """
  Generates an arangodb schema.

  Takes in the field commands and generates a schema.
  """
  @spec generate_schema([tuple()], Keyword.t()) :: t()
  def generate_schema(commands, opts \\ [])
  def generate_schema([], _opts), do: nil

  def generate_schema(commands, opts) do
    %{
      rule: convert(commands, opts),
      level: get_level(opts),
      message: Keyword.get(opts, :message, @default_msg)
    }
  end

  @doc """
  Converts commands to a json schema
  """
  def convert(commands, opts) do
    opts =
      Keyword.update(opts, :schema, %{}, fn schema ->
        get_in(schema, ["rule", "properties"]) |> atom_keys()
      end)

    command_to_schema({nil, commands, []}, opts)
    |> Map.delete(:type)
  end

  defp command_to_schema({_name, :string, command_opts}, _opts) do
    %{type: "string"}
    |> maybe_add_opt(command_opts, :minLength, :min_length)
    |> maybe_add_opt(command_opts, :maxLength, :max_length)
    |> maybe_add_opt(command_opts, :pattern)
    |> maybe_add_opt(command_opts, :format)
    |> maybe_add_opt(command_opts, :contentEncoding, :content_encoding)
    |> maybe_add_opt(command_opts, :contentMediaType, :content_media_type)
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, :enum, command_opts}, _opts) do
    %{enum: Keyword.fetch!(command_opts, :values)}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, :const, command_opts}, _opts) do
    %{const: Keyword.fetch!(command_opts, :value)}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, :boolean, _command_opts}, _opts) do
    %{type: "boolean"}
  end

  defp command_to_schema({_name, :map, command_opts}, _opts) do
    %{type: "object"}
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, {:array, type}, command_opts}, _opts) do
    %{type: "array", items: %{type: type}}
    |> maybe_add_opt(command_opts, :minItems, :min_items)
    |> maybe_add_opt(command_opts, :maxItems, :max_items)
    |> maybe_add_opt(command_opts, :uniqueItems, :unique_items)
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({name, [_ | _] = subcommands, command_opts}, opts) do
    opts = sub_level_schema(opts, name)

    content =
      Enum.reduce(subcommands, Keyword.fetch!(opts, :schema), &process_subcommand(&1, opts, &2))

    %{
      type: "object",
      properties: content
    }
    |> maybe_add_opt(command_opts, :patternProperties, :pattern_properties)
    |> maybe_add_opt(command_opts, :additionalProperties, :additional_properties)
    |> maybe_add_opt(command_opts, :required)
    |> maybe_add_opt(command_opts, :minProperties, :min_properties)
    |> maybe_add_opt(command_opts, :maxProperties, :max_properties)
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, numeric, command_opts}, _opts)
       when numeric in [:integer, :number, :decimal, :float] do
    %{type: "number"}
    |> maybe_add_opt(command_opts, :minimum)
    |> maybe_add_opt(command_opts, :exclusiveMinimum, :exclusive_minimum)
    |> maybe_add_opt(command_opts, :maximum)
    |> maybe_add_opt(command_opts, :exclusiveMaximum, :exclusive_maximum)
    |> maybe_add_opt(command_opts, :multipleOf, :multiple_of)
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({name, :date, command_opts}, opts) do
    command_to_schema(
      {name, :string, Keyword.put(command_opts, :format, "date")},
      opts
    )
  end

  defp command_to_schema({name, datetime, command_opts}, opts)
       when datetime in [:datetime, :utc_datetime, :utc_datetime_usec] do
    command_to_schema(
      {name, :string, Keyword.put(command_opts, :format, "date-time")},
      opts
    )
  end

  defp command_to_schema({name, :uuid, command_opts}, opts) do
    pattern =
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

    command_to_schema(
      {name, :string, Keyword.put(command_opts, :pattern, pattern)},
      opts
    )
  end

  defp command_to_schema({name, datetime, command_opts}, opts)
       when datetime in [:naive_datetime, :naive_datetime_usec] do
    pattern =
      "^(-?(?:[1-9][0-9]*)?[0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])T(2[0-3]|[01][0-9]):([0-5][0-9]):([0-5][0-9])(\.[0-9]+)?(Z|[+-](?:2[0-3]|[01][0-9]):[0-5][0-9])?$"

    command_to_schema(
      {name, :string, Keyword.put(command_opts, :pattern, pattern)},
      opts
    )
  end

  defp process_subcommand({:add, name, type, command_opts}, opts, acc) do
    Map.put(acc, name, command_to_schema({name, type, command_opts}, opts))
  end

  defp process_subcommand({:modify, name, type, command_opts}, opts, acc) do
    Map.replace(acc, name, command_to_schema({name, type, command_opts}, opts))
  end

  defp process_subcommand({:remove, name}, _opts, acc) do
    Map.delete(acc, name)
  end

  defp process_subcommand({:remove, name, _type, _command_opts}, _opts, acc) do
    Map.delete(acc, name)
  end

  defp process_subcommand({:rename, original, new}, _opts, acc) do
    Map.new(acc, fn
      {^original, val} -> {new, val}
      pair -> pair
    end)
  end

  defp maybe_add_opt(object, opts, target, key \\ nil) do
    key = if is_nil(key), do: target, else: key

    if val = Keyword.get(opts, key) do
      validate_opt!(key, val)

      Map.put(object, target, val)
    else
      object
    end
  end

  @non_neg_fields [
    :min_properties,
    :max_properties,
    :min_length,
    :max_length,
    :multiple_of
  ]

  @integer_fields [
    :minimum,
    :maximum,
    :exclusive_minimum,
    :exclusive_maximum
  ]

  defp validate_opt!(:comment, value) when is_binary(value), do: true
  defp validate_opt!(:pattern, value) when is_binary(value), do: true
  defp validate_opt!(:format, value) when is_binary(value), do: true

  defp validate_opt!(:pattern_properties, value) when is_map(value), do: true

  defp validate_opt!(:additional_properties, value) when is_boolean(value) or is_map(value),
    do: true

  defp validate_opt!(:required, value) when is_list(value), do: Enum.all?(value, &is_binary/1)

  defp validate_opt!(prop_nums, value)
       when prop_nums in @non_neg_fields and
              is_integer(value) and value > 0,
       do: true

  defp validate_opt!(prop_nums, value)
       when prop_nums in @integer_fields and
              is_integer(value),
       do: true

  defp validate_opt!(key, _), do: raise(ArgumentError, "invalid option type given for #{key} key")

  defp get_level(opts) do
    level = Keyword.get(opts, :level, :strict)

    unless level in @available_levels do
      raise(
        ArgumentError,
        "invalid schema level, must be one of [#{Enum.join(@available_levels, ",")}]"
      )
    end

    level
  end

  defp sub_level_schema(opts, nil), do: Keyword.put(opts, :schema, %{})

  defp sub_level_schema(opts, name) do
    if schema = Keyword.get(opts, :schema) do
      Keyword.put(opts, :schema, get_in(schema, [name, :properties]) || %{})
    else
      Keyword.put(opts, :schema, %{})
    end
  end

  defp atom_keys(%{} = string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), atom_keys(val)}
  end

  defp atom_keys(val), do: val

  defp apply_nullable(object, opts) do
    if Keyword.get(opts, :null, true) do
      Map.update!(object, :type, &[&1, "null"])
    else
      object
    end
  end
end
