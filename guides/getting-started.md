# Getting started

<!-- TODO: A short "first five minutes" tutorial. -->

## Install

Add to `mix.exs`:

```elixir
def deps do
  [{:flicker, "~> 0.1"}]
end
```

Then fetch:

```bash
mix deps.get
```

## Your first call

```elixir
Flicker.hello()
# => :world
```
