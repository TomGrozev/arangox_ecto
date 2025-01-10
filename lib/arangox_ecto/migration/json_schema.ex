defmodule ArangoXEcto.Migration.JsonSchema do
  @moduledoc """
  Converts migration command to JSON Schema.

  This will take a list of commands that are generated from a migration and convert it into a
  JSON Schema representation.

  ArangoDB takes a JSON schema that has 3 arguments:

    * `:rule` - the actual JSON schema to be checked (this is where the commands get converted to)
    * `:level` - how ArangoDB checks a document against the schema
    * `:message` - a message that is returned when the schema doesn't match

  For more info on how to change the `:level` and `:message`, see `generate_schema/2`.

  This is based on the JSON Schema definition, more info can be found
  [here](https://json-schema.org/). Note that not all of the JSON Schema attributes are implemented,
  so check the documentation in this module for what is implemented.

  For example, take the following migration.

      create collection(:users) do
        add :first_name, :string, comment: "first_name column"
        add :last_name, :string
        add :gender, :integer
        add :age, :integer
        add :location, :map

        timestamps()
      end

  This will result in the following JSON Schema.

      %{
        rule: %{
          type: "object",
          properties: %{
            first_name: %{
              type: "string",
              comment: "first_name column"
            },
            last_name: %{type: "string"},
            gender: %{type: "integer"},
            age: %{type: "integer"},
            location: %{type: "map"},
            inserted_at: %{
              type: "string",
              pattern: "<regex pattern>"
            },
            updated_at: %{
              type: "string",
              pattern: "<regex pattern>"
            }
          }
        },
        level: :strict,
        message:
          "The document does not match the schema. Please ensure the document matches the json schema."
      }
  """
  @moduledoc since: "2.0.0"

  @type field ::
          :string
          | :integer
          | :number
          | :decimal
          | :float
          | :enum
          | :const
          | :date
          | :datetime
          | :utc_datetime
          | :utc_datetime_usec
          | :naive_datetime
          | :naive_datetime_usec
          | :uuid
          | :boolean
          | :map
          | {:array, field()}

  @type action :: :add | :modify | :remove | :rename
  @type command :: {action(), atom(), field() | [command()], Keyword.t()}

  @type level :: :none | :new | :moderate | :strict

  @type t :: %{rule: map(), level: level(), message: String.t()}

  @available_levels [:none, :new, :moderate, :strict]

  @default_msg "The document does not match the schema. Please ensure the document matches the json schema."

  @doc """
  Generates an ArangoDB schema.

  Takes in the field commands and generates a schema.

  ## Options

    * `:level` - the level to use for ArangoDB schema checking. Available options are:
      #{Enum.map_join(@available_levels, ", ", &inspect/1)}. `:strict` is the default.
      Please refer to the ArangoDB docs for what these mean.
      
    * `:message` - a message to be returned when a document doesn't match the schema.

    Any other options are passed to `convert/2`.
  """
  @spec generate_schema([command()], Keyword.t()) :: t()
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
  Converts commands to a JSON schema

  This will take commands in the format of:

      {action, name, type_or_sub_commands, options}

  For example, take the following:

      {:add, :first_name, :string, comment: "Some comment"}

  Will result in the following part of the JSONSchema.

      %{"type" => "string", :"$comment" => "Some comment"}

  The type and options passed are validated to ensure they are the right type.

  ## Available actions

  The available actions are available in `t:action/0`

  ## Available types

    * `:string` - represents a string with the following options available
      * `:min_length` - Minimum length of the string
      * `:max_length` - Maximum length of the string
      * `:pattern` - A string regex pattern
      * `:format` - A validator for the format, available ones can be found [here](https://json-schema.org/understanding-json-schema/reference/string#built-in-formats).
      * `:content_encoding` - The content encoding to use, available values can be found [here](https://json-schema.org/understanding-json-schema/reference/non_json_data#contentencoding)
      * `:content_media_type` - The content media type to use, available values can be found [here](https://json-schema.org/understanding-json-schema/reference/non_json_data#contentencoding)
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

    * `:integer`, `:number`, `:decimal` or `:float` - represents a numeric value with the following options available
      * `:minimum` - Minimum value of the number
      * `:exclusive_minimum` - Minimum value of the number exclusive
      * `:maximum` - Maximum value of the number
      * `:exclusive_maximum` - Maximum value of the number exclusive
      * `:multiple_of` - A value the number must be a multiple of
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

    * `:enum` - a set of values
      * `:values` - A list of possible values
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

    * `:const` - a value
      * `:value` - A list of possible values
      * `:comment` - A comment to add to the object, it has no functional application

    * `:date` - represents a date
      * This essentially just calls `:string` with format=date. Accepts the same parameters as `:string`

    * `:datetime`, `:utc_datetime` or `:utc_datetime_usec` - represents a datetime
      * This essentially just calls `:string` with format=date-time. Accepts the same parameters as `:string`

    * `:naive_datetime` or `:naive_datetime_usec` - represents a naive datetime
      * This essentially just calls `:string` with a custom pattern to validate a naive datetime. Accepts the same parameters as `:string`

    * `:uuid` - represents a uuid
      * This essentially just calls `:string` with a custom pattern to validate a uuid. Accepts the same parameters as `:string`

    * `:boolean` - represents a boolean with the following options available
      * `:comment` - A comment to add to the object, it has no functional application

    * `:map` - represents a map with the following options available
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

    * `{:array, sub_type}` - represents an array with the specified `sub_type` which can be any type
      * `:min_items` - Minimum number of items in the array
      * `:max_items` - Maximum number of items in the array
      * `:unique_items` - Boolean if each item must be unique
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

    * `[sub_command]` - an object with sub properties where `sub_command` is a command
      * `:pattern_properties` - A pattern for property keys, see [the docs](https://json-schema.org/understanding-json-schema/reference/object#patternProperties) for more info
      * `:additional_properties` - The type of non-listed properties (or false to disallow), see [the docs](https://json-schema.org/understanding-json-schema/reference/object#additionalproperties) for more info
      * `:required` - A list of required properties
      * `:min_properties` - The minimum number of properties
      * `:max_properties` - The maximum number of properties
      * `:comment` - A comment to add to the object, it has no functional application
      * `:null` - If the value can be null

  ## Options

    * `:schema` - the existing schema to apply the migrations to. This is useful so that a schema
      isn't overwritten and is instead updated.
  """
  @spec convert([command()], Keyword.t()) :: map()
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
    %{type: "string", enum: Keyword.fetch!(command_opts, :values)}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, :const, command_opts}, _opts) do
    %{type: "string", const: Keyword.fetch!(command_opts, :value)}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, :boolean, command_opts}, _opts) do
    %{type: "boolean"}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
  end

  defp command_to_schema({_name, :map, command_opts}, _opts) do
    %{type: "object"}
    |> maybe_add_opt(command_opts, :"$comment", :comment)
    |> apply_nullable(command_opts)
  end

  defp command_to_schema({_name, {:array, type}, command_opts}, opts) do
    sub_type = command_to_schema({:items, type, command_opts}, opts)

    %{type: "array", items: sub_type}
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
    pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

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

    if level not in @available_levels do
      raise(
        ArgumentError,
        "invalid schema level, must be one of [#{Enum.join(@available_levels, ",")}]"
      )
    end

    level
  end

  defp sub_level_schema(opts, nil), do: opts

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
