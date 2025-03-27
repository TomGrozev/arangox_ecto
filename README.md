# ArangoX Ecto

[![github.com](https://img.shields.io/github/actions/workflow/status/TomGrozev/arangox_ecto/ci.yml)](https://github.com/TomGrozev/arangox_ecto/actions)
[![hex.pm](https://img.shields.io/hexpm/v/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/dt/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![hex.pm](https://img.shields.io/hexpm/l/arangox_ecto.svg)](https://hex.pm/packages/arangox_ecto)
[![github.com](https://img.shields.io/github/last-commit/TomGrozev/arangox_ecto.svg)](https://github.com/TomGrozev/arangox_ecto)

ArangoXEcto is an all-in-one Arango database adapter for the Elixir Ecto package. It has full support for **Graphing**, **Arango Search**,
**Geo Functions**, **AQL Integration**, amongst other features.

## Table of Contents

- [ArangoX Ecto](#arangox-ecto)
  - [Table of Contents](#table-of-contents)
  - [About The Project](#about-the-project)
    - [Built With](#built-with)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
  - [Roadmap](#roadmap)
  - [Contributing](#contributing)
  - [License](#license)
  - [Contact](#contact)
  - [Acknowledgements](#acknowledgements)

## About The Project

After playing around with different packages that implemented ArangoDB in Elixir, I found that there wasn't a package
that suited my needs. I needed ArangoDB to work with Ecto seamlessly but there was no up-to-date adapter for Ecto available.
ArangoX Ecto uses the power of ArangoX to communicate with ArangoDB and Ecto for the API in Elixir. Ecto is integrated
with many other packages and can now be used with ArangoDB thanks to this package.

### Built With

- [Arangox](https://github.com/ArangoDB-Community/arangox)

## Getting Started

To get the adapter integrated with your project, follow these simple steps.

### Prerequisites

- Elixir 1.16.3+ / Erlang OTP 25.3.2.12+
  (Others may versions may work but this is the oldest it is tested on)

### Installation

Add the following line to your mix dependencies to get started.

```elixir
{:arangox_ecto, "~> 2.0"}
```

You can find more information in the [Getting Started
Guide](https://hexdocs.pm/arangox_ecto/getting-started.html).

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

- [mpoeter](https://github.com/mpoeter) - Wrote the original Ecto Query to AQL code
- [kianmeng](https://github.com/kianmeng) - README changes & CI dep change
- [bodbdigr](https://github.com/bodbdigr) - Fixed AQL query typespec
- [hengestone](https://github.com/hengestone) - Added option to use different
  migrations directory
