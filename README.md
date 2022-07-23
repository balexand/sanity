# Sanity

[![Package](https://img.shields.io/badge/-Package-important)](https://hex.pm/packages/sanity) [![Documentation](https://img.shields.io/badge/-Documentation-blueviolet)](https://hexdocs.pm/sanity)

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
