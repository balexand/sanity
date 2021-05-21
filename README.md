# Sanity

A client library for the Sanity CMS API.

## Installation

The package can be installed by adding `sanity` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sanity, "~> 0.3.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/sanity](https://hexdocs.pm/sanity/Sanity.html).

## Example

```elixir
Sanity.query(~S'*[_type == "product"]')
|> Sanity.request(project_id: "abcdefgh", dataset: "production")
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
