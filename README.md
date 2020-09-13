[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]



<br />
<p align="center">
  <a href="https://github.com/TomGrozev/arangox_ecto">
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">ArangoX Ecto</h3>

  <p align="center">
    An adapter for ArangoDB and Ecto that support full graph functionality.
    <br />
    <a href="https://hexdocs.pm/arangox_ecto"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/TomGrozev/arangox_ecto">View Demo</a>
    ·
    <a href="https://github.com/TomGrozev/arangox_ecto/issues">Report Bug</a>
    ·
    <a href="https://github.com/TomGrozev/arangox_ecto/issues">Request Feature</a>
  </p>
</p>



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

To get a local copy up and running follow these simple steps.

### Prerequisites

* Elixir

### Installation

Add the following line to your mix dependencies.

```elixir
{:arangox_ecto, git: "https://github.com/TomGrozev/arangox_ecto", tag: "0.5"}
```



## Usage

**TODO: Add usage examples**

_For more examples, please refer to the [Documentation](https://hexdocs.pm/arangox_ecto)_



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

Your Name - [@tomgrozev](https://twitter.com/tomgrozev) - enquire@tomgrozev.com

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
