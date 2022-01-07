# ArangoX Ecto

[![github.com](https://img.shields.io/github/workflow/status/TomGrozev/arangox_ecto/CI.svg)](https://github.com/TomGrozev/arangox_ecto/actions)
[![hex.pm](https://img.shields.io/hexpm/v/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/dt/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/l/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![github.com](https://img.shields.io/github/last-commit/TomGrozev/arangox_ecto.svg)](https://github.com/TomGrozev/arangox_ecto)

<!-- TABLE OF CONTENTS -->
## Table of Contents

* [About the Project](#about-the-project)
  * [Built With](#built-with)
* [Getting Started](#getting-started)
  * [Prerequisites](#prerequisites)
  * [Installation](#installation)
* [Usage](#usage)
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

* Elixir 1.10+ / Erlang OTP 23+

### Installation

Add the following line to your mix dependencies to get started.

```elixir
{:arangox_ecto, "~> 0.6"}
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

#### Migration Setup

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

Using migrations should be avoided unless necessary.


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
easy with the help of the `ArangoXEcto.raw_to_struct/2` function. The same query above could be extended to also convert
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
        |> ArangoXEcto.raw_to_struct(User)

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
schema when they are first used. This will allow for more extensibility through Ecto onto the edges. The module will
be created under the closest common parent module of the passed modules plus the `Edges` alias. The order of the edge name will always be alphabetical to prevent duplicate edges.
For example, if the modules were `MyApp.Apple.User` and `MyApp.Apple.Banana.Post` then the edge would be created at
`MyApp.Apple.Edges.PostsUsers`. This assumes that the edge collection name was generated and not explicitly defined,
if it was `PostsUsers` would be replaced with the camel case of that collection name.

From version 1.0.0 onwards, edges are represented as traditional relationships in Ecto. This approach allows for the simplicity of simple management
of edges but the complex querying through AQL. The relationships are represented by an `outgoing/3` and `incoming/3` in the respective schemas.
For example if you wanted to create edges between A and B, with the direction A -> B then A would have `outgoing/3` and B would have `incoming/3`.
This directionality is simply for what is put in the `_from` and `_to` fields in the Arango edge collection, if you don't care about directionality, you
don't have to worry as much about which schema has `outgoing/3` and `incoming/3`.

Additionally, `one_outgoing/3` and `one_incoming/3` can be used for one-to-one relationships. These do not actually create edges but just store the `_id` of the target in a
field instead. The order of the outgoing & incoming in schemas does matter as a field will be created in the incoming schema.

Behind the scenes these outgoing & incoming helper macros are simply wrappers around the Ecto function `Ecto.Schema.many_to_many/3`.
The one-to-one outgoing & incoming macros are just wrappers around `Ecto.Schema.has_one/3` and `Ecto.Schema.belongs_to/3` respectively.
Hence once setup the regular methods for handling Ecto relationships can be used.

To learn about using the schema functions for representing graph relationships and examples, read the docs at
[ArangoXEcto.Schema](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Schema.html).

To read more about Edge Schemas and how to extend edge schemas to add additional fields, read the docs on
[ArangoXEcto.Edge](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Edge.html).

To learn how to use the helper functions (as well as other useful methods) check out the
[full documentation](https://hexdocs.pm/arangox_ecto/ArangoXEcto.html).

In order to delete a specific edge, you can do it exactly as you would any other Ecto struct
(since after all it is one) or Ecto relation.

Querying of edges can be done either through using an AQL query or by using Ecto methods.

### Further Usage

For more examples and full documentation, please refer to the [Documentation](https://hexdocs.pm/arangox_ecto).



## Roadmap

See the [open issues](https://github.com/TomGrozev/arangox_ecto/issues) for a list of proposed features (and known issues).

##### Some planned ideas:
* ☐ ~~Named Graph integrations~~
* ☑ GeoJSON
* ☑ Easier Graph level functions
* ☐ Multi-tenancy


## Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Write some awesome code
4. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
5. Push to the Branch (`git push origin feature/AmazingFeature`)
6. Open a Pull Request



## License

Distributed under the Apache 2.0 License. See `LICENSE` for more information.



## Contact

Tom Grozev - [@tomgrozev](https://twitter.com/tomgrozev) - enquire@tomgrozev.com

Project Link: [https://github.com/TomGrozev/arangox_ecto](https://github.com/TomGrozev/arangox_ecto)



## Acknowledgements

* [mpoeter](https://github.com/mpoeter) - Wrote the original Ecto Query to AQL code
* [bodbdigr](https://github.com/bodbdigr) - Fixed AQL query typespec




[contributors-shield]: https://img.shields.io/github/contributors/TomGrozev/arangox_ecto.svg?style=flat-square
[contributors-url]: https://github.com/TomGrozev/arangox_ecto/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/TomGrozev/arangox_ecto.svg?style=flat-square
[forks-url]: https://github.com/TomGrozev/arangox_ecto/network/members
[stars-shield]: https://img.shields.io/github/stars/TomGrozev/arangox_ecto.svg?style=flat-square
[stars-url]: https://github.com/TomGrozev/arangox_ecto/stargazers
[issues-shield]: https://img.shields.io/github/issues/TomGrozev/arangox_ecto.svg?style=flat-square
[issues-url]: https://github.com/TomGrozev/arangox_ecto/issues
[license-shield]: https://img.shields.io/github/license/TomGrozev/arangox_ecto.svg?style=flat-square
[license-url]: https://github.com/TomGrozev/arangox_ecto/blob/master/LICENSE
