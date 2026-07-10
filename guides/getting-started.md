# Getting started

<!-- TODO: A short "first five minutes" tutorial once the component itself
(Spec 001) ships. For now, this covers the data-source contract every
picker is built on. -->

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

## The provider contract

Everything Flicker searches or selects from is a `Flicker.Provider` — a
small behaviour with two required callbacks:

```elixir
@callback search(query :: Flicker.Query.t(), opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}
@callback fetch(values :: [term()], opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}
```

If you're on Ash, the built-in `Flicker.Providers.AshResource` is generated
for you from a resource and a few field names — most Ash users never write
a provider by hand. If you aren't on Ash, or need federated search across
multiple sources, implement the behaviour directly.

## Writing your own provider

`Flicker.Providers.Static` — a small in-memory provider — is the worked
example:

```elixir
defmodule MyApp.Providers.Http do
  @behaviour Flicker.Provider

  @impl true
  def search(%Flicker.Query{text: text}, _opts) do
    # call an external API, map its results to `Flicker.Result` structs
    {:ok, [%Flicker.Result{value: "42", label: "Example result"}]}
  end

  @impl true
  def fetch(values, _opts) do
    # resolve `values` in one call; omit any that don't resolve — this is
    # a normal partial result, not an error
    {:ok, []}
  end
end
```

See `Flicker.Provider`'s module docs for the full contract (including the
optional `facets/0` and `render_option/2` callbacks), and
`Flicker.Providers.Static` for a complete, tested implementation.
