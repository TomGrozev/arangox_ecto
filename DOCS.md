# ArangoXEcto

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
ArangoX Ecto uses the power of ArangoX to communicate with ArangoDB and Ecto for the API in Elixir. Ecto is intergrated
with many other packages and can now be used with ArangoDB thanks to this package.


### Built With

* [Arangox](https://github.com/ArangoDB-Community/arangox)



## Getting Started

To get the adapter integrated with your project, follow these simple steps.

### Prerequisites

* Elixir

### Installation

Add the following line to your mix dependencies.

```elixir
{:arangox_ecto, git: "https://github.com/TomGrozev/arangox_ecto", tag: "0.6.1"}
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

The adapter will automatically create collections if they don't already exist but there are cases where you might need
to use migrations. For example, if you needed to create indexes as well, the following would be used.

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

A lot of the time it is far more efficient to just run a raw aql query, there's a function for that.

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

After a lot of tinkering, the best solution to graph relations in with Arango and Ecto was to not use Ecto a lot.

The adapter will dynamically create and manage edge collections. Each edge collection will be created as an Ecto
schema when they are first used. This will allow for more extensibility through ecto onto the edges. The module will
be created under the closest common parent module of the passed modules plus the `Edges` alias. For example, if the
modules were `MyApp.Apple.User` and `MyApp.Apple.Banana.Post` then the edge would be created at
`MyApp.Apple.Edges.UsersPosts`. This assumes that the edge collection name was generated and not explicitly defined,
if it was `UsersPosts` would be replaced with the camelcase of that collection name.

To read more about Edge Schemas and how to extend edge schemas to add additional fields, read the docs on 
[ArangoXEcto.Edge](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Edge.html).

To create and delete edges (as well as other useful methods) check out the 
[full documentation](https://hexdocs.pm/arangox_ecto/ArangoXEcto.html).

In order to delete a specific edge, you can do it exactly as you would any other ecto struct 
(since after all it is one).

Querying of edges can be done either through using an AQL query or by using Ecto methods.

### Further Usage

For more examples and full documentation, please refer to the [Documentation](https://hexdocs.pm/arangox_ecto).



## Roadmap

See the [open issues](https://github.com/TomGrozev/arangox_ecto/issues) for a list of proposed features (and known issues).

##### Some planned ideas:
* Named Graph integrations
* Easier Graph level functions
* Multi-tenancy


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
