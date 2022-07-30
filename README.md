# Sanity

[![Package](https://img.shields.io/hexpm/v/sanity.svg)](https://hex.pm/packages/sanity) [![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/sanity) ![CI](https://github.com/balexand/sanity/actions/workflows/elixir.yml/badge.svg)

A client library for the [Sanity CMS API](https://www.sanity.io/docs/http-api).

## Installation

The package can be installed by adding `sanity` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sanity, "~> 0.11.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/sanity](https://hexdocs.pm/sanity/Sanity.html).

## Examples

```elixir
Sanity.query(~S'*[_type == "product"]')
|> Sanity.request(project_id: "abc", dataset: "production")
```

## Supported endpoints

- [x] Assets
- [x] Doc
- [ ] Export
- [ ] History
- [ ] Listen
- [x] Mutate
- [ ] Projects
- [x] Query
