# ArangoX Ecto

[![github.com](https://img.shields.io/github/actions/workflow/status/TomGrozev/arangox_ecto/ci.yml)](https://github.com/TomGrozev/arangox_ecto/actions)
[![hex.pm](https://img.shields.io/hexpm/v/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/dt/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/l/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![github.com](https://img.shields.io/github/last-commit/TomGrozev/arangox_ecto.svg)](https://github.com/TomGrozev/arangox_ecto)

ArangoXEcto is an all-in-one Arango database adapter for the Elixir Ecto package. It has full support for **Graphing**, **Arango Search**, 
**Geo Functions**, **AQL Integration**, amongst other features.

<!-- TABLE OF CONTENTS -->
## Table of Contents

- [ArangoX Ecto](#arangox-ecto)
  * [Table of Contents](#table-of-contents)
  * [About The Project](#about-the-project)
    + [Built With](#built-with)
  * [Getting Started](#getting-started)
    + [Prerequisites](#prerequisites)
    + [Installation](#installation)
  * [Usage](#usage)
    + [Static or Dynamic](#static-or-dynamic)
    + [Basic Usage](#basic-usage)
      - [Repo Setup](#repo-setup)
      - [Schema Setup](#schema-setup)
      - [Migration Setup](#migration-setup)
    + [Raw AQL queries](#raw-aql-queries)
    + [Graph Relations](#graph-relations)
      - [Generation of Edge Modules](#generation-of-edge-modules)
      - [Graphing in Ecto](#graphing-in-ecto)
      - [One-to-One relationships](#one-to-one-relationships)
      - [How it works](#how-it-works)
      - [Example](#example)
      - [More information](#more-information)
    + [Arango Search](#arango-search)
    + [Further Usage](#further-usage)
  * [Roadmap](#roadmap)
  * [Contributing](#contributing)
  * [License](#license)
  * [Contact](#contact)
  * [Acknowledgements](#acknowledgements)



## About The Project

After playing around with different packages that implemented ArangoDB in Elixir, I found that there wasn't a package
that suited my needs. I needed ArangoDB to work with Ecto seamlessly but there was no up-to-date adapter for Ecto available.
ArangoX Ecto uses the power of ArangoX to communicate with ArangoDB and Ecto for the API in Elixir. Ecto is integrated
with many other packages and can now be used with ArangoDB thanks to this package.

From version 1.0.0 onward graph relationships work seamlessly in Ecto.


### Built With

* [Arangox](https://github.com/ArangoDB-Community/arangox)



## Getting Started

To get the adapter integrated with your project, follow these simple steps.

### Prerequisites

* Elixir 1.12.3+ / Erlang OTP 22.2+
(Others may versions may work but this is the oldest it is tested on)

### Installation

Add the following line to your mix dependencies to get started.

```elixir
{:arangox_ecto, "~> 1.3"}
```

## Usage

To connect to the database you need to specify the config values like so:

```elixir
config :my_app, MyApp.Repo,
  database: "my_db",
  endpoints: "http://1.2.3.4:8529"
```

Only `database` and `endpoints` are required but there are other available options can be found in the [Arangox docs](https://hexdocs.pm/arangox/Arangox.html#start_link/1).

The database should be setup using
```shell
$ mix ecto.setup.arango
```

### Static or Dynamic
In addition to default config variables, the `static` boolean config option can be passed to force the use of migrations. By default the value is `false` and collections that don't exist will be created on insert and on query no error will be raised. If set to `true`, any collections that do not exist on insert or query will result in an error to be raised.

Whether dynamic (default) or static is chosen defends on the database design of the project. For a production setup where lots of control is required, it is recommended to have `static` set to `true`.

If using static in production is better why is dynamic the default? Dynamic mode is the default because it is easier for development and testing then after that point static mode can be turned on for production.


### Basic Usage

#### Repo Setup

To use the adapter in your repo, make sure your repo uses the `ArangoXEcto.Adapter` module for the adapter.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: ArangoXEcto.Adapter
end
```

#### Schema Setup

Since ArangoDB uses a slightly different id system, your schema must use the `ArangoXEcto.Schema` instead of
`Ecto.Schema`.

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

The `options/1` and `indexes/1` options can be optionally called inside the schema to set options and indexes to be created in dynamic mode. These options will have no effect in static mode.

For example, if you wanted to use a uuid as the key type and create an index on the email the following can be used.
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


#### Migration Setup

**Using migrations is only required in static mode**

If in dynamic mode (default), the adapter will automatically create collections if they don't already exist but there are cases where you might need
to use a static system and hence migrations are required. For example, if you needed to create indexes as well, the following would be used.

Refer to [ArangoXEcto.Migration](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Migration.html) for more information on usage.

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
    use ArangoXEcto.Migration

    def up do
      create(collection(:users))

      create(index("users", [:email]))
    end

    def down do
      drop(collection(:users))
    end
end
```


### Raw AQL queries

A lot of the time it is far more efficient to just run a raw AQL query, there's a function for that.

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

This is awesome functionality, but a lot of the time we will want to resemble a specific struct. This is actually quite
easy with the help of the `ArangoXEcto.load/2` function. The same query above could be extended to also convert
the output:

```elixir
ArangoXEcto.aql_query(
    Repo,
    "FOR var in users FILTER var.first_name == @fname AND var.last_name == @lname RETURN var",
    fname: "John",
    lname: "Smith"
  )
  |> case do
      {:ok, results} ->
        results
        |> ArangoXEcto.load(User)

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

This is clearly a much better representation of the result and can be used in further Ecto methods.


### Graph Relations

The adapter will dynamically create and manage edge collections. Each edge collection will be created as an Ecto
schema when they are first used. This will allow for more extensibility through Ecto onto the edges.


#### Generation of Edge Modules
The module will be created under the closest common parent module of the passed modules plus the `Edges` alias. The order of the edge name will always be alphabetical to prevent duplicate edges.
For example, if the modules were `MyApp.Apple.User` and `MyApp.Apple.Banana.Post` then the edge would be created at
`MyApp.Apple.Edges.PostsUsers`. This assumes that the edge collection name was generated and not explicitly defined,
if it was `PostsUsers` would be replaced with the camel case of that collection name (i.e. `posts_users`).

#### Graphing in Ecto
From version 1.0.0 onwards, edges are represented as traditional relationships in Ecto. This approach allows for the simplicity of simple management
of edges but the complex querying through AQL.

The relationships are represented by an `outgoing/3` and `incoming/3` in the respective schemas.
For example if you wanted to create edges between A and B, with the direction A -> B then A would have `outgoing/3` and B would have `incoming/3`.
This directionality is simply for what is put in the `_from` and `_to` fields in the Arango edge collection, if you don't care about directionality, you
don't have to worry as much about which schema has `outgoing/3` and `incoming/3`.

#### One-to-One relationships
Additionally, `one_outgoing/3` and `one_incoming/3` can be used for one-to-one relationships. These do not actually create edges but just store the `_id` of the target in a
field instead. The order of the outgoing & incoming in schemas does matter as a field will be created in the incoming schema.

#### One-to-Many relationships
Graph relationships are a good substitute for many-to-many relationships in a traditional relational database. One-to-Many relationships in ArangoDB will function exactly the same as in a relational database. Therefore you can just use the regular `Ecto.Schema.has_many/3` and `Echo.Schema.belongs_to/3` functions as documented in the [Ecto docs](https://hexdocs.pm/ecto/2.2.11/associations.html).

#### How it works
Behind the scenes these outgoing & incoming helper macros are simply wrappers around the Ecto function `Ecto.Schema.many_to_many/3`.
The one-to-one outgoing & incoming macros are just wrappers around `Ecto.Schema.has_one/3` and `Ecto.Schema.belongs_to/3` respectively.
Hence once setup the regular methods for handling Ecto relationships can be used.

In order to delete a specific edge, you can do it exactly as you would any other Ecto struct
(since after all it is one) or Ecto relation.

Querying of edges can be done either through using an AQL query or by using Ecto methods.

#### Example
Let's say you wanted to create an edge between your `Post` and `User` schema. You could implement it as follows:

```elixir
defmodule MyProject.User do
  use ArangoXEcto.Schema

  schema "users" do
    field :name, :string

    # Will use the automatically generated edge
    outgoing :posts, MyProject.Post

    # Or use the UserPosts edge
    # outgoing :posts, MyProject.Post, edge: MyProject.UserPosts
  end
end

defmodule MyProject.Post do
  use ArangoXEcto.Schema

  schema "posts" do
    field :title, :string

    # Will use the automatically generated edge
    incoming :users, MyProject.User

    # Or use the UserPosts edge
    # incoming :users, MyProject.User, edge: MyProject.UserPosts
  end
end
```

#### More information
To learn about using the schema functions for representing graph relationships and examples, read the docs at
[ArangoXEcto.Schema](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Schema.html).

To read more about Edge Schemas and how to extend edge schemas to add additional fields, read the docs on
[ArangoXEcto.Edge](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Edge.html).

To learn how to use the helper functions (as well as other useful methods) check out the
[full documentation](https://hexdocs.pm/arangox_ecto/ArangoXEcto.html).

### Arango Search

As of version 1.3.0 Arango Search functionality is built in. This builds off of the Ecto schema module for views so they can be searched and interacted with like 
regular collections. The view schemas are not exactly the same as collection or edge schemas because the views don't actually store or hold any data and aren't 
structs themselves. Views act as alias interfaces that over the collections and edge schemas.

#### Querying 

Querying views works exactly the same as querying a regular collection or edge schema. For example, the following will work as you would expect.

```elixir
# Module definition
defmodule UsersView do
  use ArangoXEcto.View

  alias ArangoXEcto.View.Link

  view "user_search" do
    primary_sort(:created_at, :asc)

    store_value([:first_name], :lz4)

    link(User, %Link{
      includeAllFields: true,
      fields: %{
        last_name: %Link{
          analyzers: [:text_en]
        }
      }
    })

    options(primarySortCompression: :lz4)
  end
end

# Querying
iex> Repo.all(UsersView)
[%User{first_name: "John", last_name: "Smith"}, _]
```

In addition to regular querying ArangoDB has the AQL `SEARCH` function for performing searches on views. This is implemented in ArangoXEcto using an additional 
Ecto query macro. The `search/3` and `or_search/3` macros are provided to utalise this functionality. Details of how to use these functions can be found in 
[ArangoXEcto.Query](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Query.html) and the [ArangoXEcto.View](https://hexdocs.pm/arangox_ecto/ArangoXEcto.View.html) modules.

Behind the scenes the `search/3` and `or_search/3` are just wrappers around the Ecto where clause that gets unwrapped at the point when the AQL query is generated.

#### Analyzers

Analyzers can also be defined from within an analyzer module. Refer to the [ArangoXEcto.Analyzer](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html) module for documentation.


### Further Usage

For more examples and full documentation, please refer to the [Documentation](https://hexdocs.pm/arangox_ecto).


## Roadmap

See the [the roadmap](https://github.com/users/TomGrozev/projects/1) for a list of proposed features (and known issues) planned.


## Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.

Checkout the [Contributing Guide](https://github.com/TomGrozev/arangox_ecto/blob/master/CONTRIBUTING.md).


## License

Distributed under the Apache 2.0 License. See [LICENSE](https://github.com/TomGrozev/arangox_ecto/blob/master/LICENSE) for more information.



## Contact

Project Home: [https://github.com/TomGrozev/arangox_ecto](https://github.com/TomGrozev/arangox_ecto)



## Acknowledgements

* [mpoeter](https://github.com/mpoeter) - Wrote the original Ecto Query to AQL code
* [kianmeng](https://github.com/kianmeng) - README changes & CI dep change
* [bodbdigr](https://github.com/bodbdigr) - Fixed AQL query typespec
* [hengestone](https://github.com/hengestone) - Added option to use different migrations directory
