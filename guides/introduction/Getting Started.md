# Getting Started

This is an introduction on how to use the [ArangoXEcto](https://github.com/TomGrozev/arangox_ecto)
package, an ArangoDB adapter for Ecto. This adapts the various facets of the
Ecto implementation to work for graph databases.

This guide will cover the basics of using ArangoXEcto, including creating,
reading, updating and deleting records.

> #### Note {: .error}
>
> You must already have an ArangoDB database setup

## Adding ArangoXEcto to your project

Add the following line to your mix dependencies to get started.

```elixir
{:arangox_ecto, "~> 2.0"}
```

To install these dependencies, we will run this command:

```shell
mix deps.get
```

This will also install the `Arangox` dependency which is used for the
communication with the Arango database.

To connect to the database you need to specify the config values like so:

```elixir
config :my_app, MyApp.Repo,
  database: "my_db",
  endpoints: "http://1.2.3.4:8529",
  username: "root",
  password: "root",
```

Only `database` and `endpoints` are required but there are other available
options can be found in the [Arangox docs](https://hexdocs.pm/arangox/Arangox.html#start_link/1).

The database should be setup using the following.

```shell
mix ecto.create
```

### Static or Dynamic

In addition to default config variables, the `static` boolean config option can
be passed to force disable use of migrations. By default the value is `true`
and hence the by default it is in static mode and migrations are required.

If in dynamic mode collections that don't exist will be created on insert and
on query no error will be raised. If set to `true` (default), any collections
that do not exist on insert or query will result in an error being raised.

Whether dynamic or static is chosen depends on the database design of the
project. For a production setup where lots of control is required, it is
recommended to have `static` set to `true`, which is the default.

#### Why even have dynamic mode?

Dynamic mode can be easier for development and testing (especially when you
don't know what the database structure will look like) then after that point
static mode can be turned on for production.

## Repo Setup

To use the adapter in your repo, make sure your repo uses the `ArangoXEcto.Adapter` module for the adapter.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: ArangoXEcto.Adapter
end
```

## Schema Setup

Since ArangoDB uses a slightly different id system, your schema must use the
`ArangoXEcto.Schema` instead of `Ecto.Schema`.

```elixir
defmodule MyApp.Accounts.User do
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
```

### Dynamic Mode options and indexes

The `ArangoXEcto.Schema.options/1` and `ArangoXEcto.Schema.indexes/1` options
can be optionally called to set options and indexes to be created in dynamic
mode. These options will have no effect in static mode.

For example, if you wanted to use a UUID as the key type and create an index
on the email the following can be used.

```elixir
defmodule MyApp.Accounts.User do
    use ArangoXEcto.Schema
    import Ecto.Changeset

    options [
      keyOptions: %{type: :uuid}
    ]

    indexes [
      [fields: [:email]]
    ]

    schema "users" do
      field :email, :string

      timestamps()
    end

    @doc false
    def changeset(app, attrs) do
      app
      |> cast(attrs, [:first_name, :last_name])
      |> validate_required([:first_name, :last_name])
    end
end
```

Please refer to [the Schema documentation](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Schema.html) for more information on the available options.

## Migrations

> #### Note {: .info}
>
> **Using migrations is only required in static mode (the default)**
> If in dynamic mode, the adapter will automatically create collections if they
> don't already exist.

Refer to [ArangoXEcto.Migration](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Migration.html)
for more information on usage.

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
    use ArangoXEcto.Migration

    def change do
      create collection(:users) do
        add :first_name, :string, comment: "first_name column"
        add :last_name, :string

        timestamps()
      end

      create index(:users, [:email])
    end
end
```

## Raw AQL queries

A lot of the time it is far more efficient to just run a raw AQL query, there's
a function for that.

```elixir
ArangoXEcto.aql_query(
    Repo,
    "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
    fname: "John",
    lname: "Smith"
  )
```

This query will return a result such as:

```elixir
{:ok,
    [
        %{
          "_id" => "users/12345",
          "_key" => "12345",
          "_rev" => "_bHZ8PAK---",
          "first_name" => "John",
          "last_name" => "Smith"
        }
    ]}
```

This is awesome functionality, but a lot of the time we will want to resemble a
specific struct. This is actually quite easy with the help of the
`ArangoXEcto.load/2` function. The same query above could be extended to also
convert the output:

```elixir
ArangoXEcto.aql_query(
    Repo,
    "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
    fname: "John",
    lname: "Smith"
  )
  |> case do
      {:ok, results} ->
        ArangoXEcto.load(results, User)

      {:error, _reason} -> []
  end
```

This will return something like:

```elixir
[
    %User{
      id: "12345",
      first_name: "John",
      last_name: "Smith"
    }
]
```

This is clearly a much better representation of the result and can be used in
further Ecto methods.

## Graph relations

You can find out how to write graph relations in the [Graphing
Guide](https://hexdocs.pm/arangox_ecto/graphing.html)

## More information

To learn about using the schema functions for representing graph relationships and examples, read the docs at
[ArangoXEcto.Schema](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Schema.html).

To read more about Edge Schemas and how to extend edge schemas to add additional fields, read the docs on
[ArangoXEcto.Edge](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Edge.html).

To learn how to use the helper functions (as well as other useful methods) check out the
[full documentation](https://hexdocs.pm/arangox_ecto/ArangoXEcto.html).

For more examples and full documentation, please refer to the [Documentation](https://hexdocs.pm/arangox_ecto).
