# Writing your own provider

Tier 1 declarative config (`resource` + `search` + `option_label`) covers
most cases by compiling to the built-in `Flicker.Providers.AshResource`.
Reach for Tier 2 — implementing `Flicker.Provider` yourself — when the data
source isn't a single Ash resource: federated search across several
resources, a non-Ash source (an HTTP API, an in-memory list, a cache), or
custom result shaping Tier 1's options don't cover.

## The contract

`Flicker.Provider` is two required callbacks and two optional ones:

```elixir
@callback search(query :: Flicker.Query.t(), opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}

@callback fetch(values :: [term()], opts :: keyword()) ::
            {:ok, [Flicker.Result.t()]} | {:error, term()}

@callback facets() :: [Flicker.Facet.t()]
@callback render_option(result :: Flicker.Result.t(), assigns :: map()) :: term()
```

`search/2` answers "what matches what's typed so far?" `fetch/2` answers
"resolve these already-selected values back to display structs" — in one
call for the whole list (ADR-003), not one call per value. `facets/0` and
`render_option/2` are optional; implement them only if the provider needs
faceted-search support or custom option markup.

A provider is identified by a bare module, or a `{module, opts}` tuple
carrying static config. Core code never calls these callbacks directly —
it always goes through `Flicker.Provider.run_search/3` and
`Flicker.Provider.run_fetch/3`, which merge `opts` and normalise the
return value, catching a provider that raises or returns a malformed
shape into `{:error, term()}` rather than crashing the caller.

## Worked example: `Flicker.Providers.Static`

`Flicker.Providers.Static` is Flicker's own reference implementation — a
small in-memory provider backed by a fixed list of `Flicker.Result`
structs, configured with `{Flicker.Providers.Static, results: [...]}`. It
proves the contract stands alone with no Ash dependency, and it's what
Flicker's own component tests use as a test double.

```elixir
defmodule Flicker.Providers.Static do
  @behaviour Flicker.Provider

  alias Flicker.{Query, Result}

  @impl true
  def search(%Query{text: text}, opts) do
    results = Keyword.get(opts, :results, [])
    limit = Keyword.get(opts, :limit)

    matched =
      results
      |> Enum.filter(&matches?(&1, text))
      |> maybe_limit(limit)

    {:ok, matched}
  end

  @impl true
  def fetch(values, opts) do
    results = Keyword.get(opts, :results, [])
    wanted = MapSet.new(values, &to_string/1)

    {:ok, Enum.filter(results, &MapSet.member?(wanted, to_string(&1.value)))}
  end

  defp matches?(_result, ""), do: true

  defp matches?(%Result{label: label, sublabel: sublabel}, text) do
    downcased = String.downcase(text)
    contains?(label, downcased) or contains?(sublabel, downcased)
  end

  defp contains?(nil, _text), do: false
  defp contains?(field, text), do: field |> String.downcase() |> String.contains?(text)

  defp maybe_limit(results, nil), do: results
  defp maybe_limit(results, limit), do: Enum.take(results, limit)
end
```

Three things worth calling out, all general lessons for any provider:

- **A blank query matches everything.** `search/2` treats `query.text ==
  ""` as "return the (optionally limited) full list" rather than an
  empty result set — the same behaviour a picker's open-with-nothing-typed
  state expects from a real backend, which typically shows a default
  listing rather than nothing.
- **`fetch/2` resolves by string, not strict equality.** Form-field
  mode's `field.value` always arrives as a string (from params, or a
  LiveSocket reconnect); a result's `:value` is commonly an integer or
  atom. Normalising both sides with `to_string/1` before comparing is
  what makes a preselected value actually resolve on first render.
- **Unresolvable values are silently dropped, not an error.** If a
  `fetch/2` value has no matching result — a deleted record, or (for a
  real provider) one a policy now hides — it's just absent from the
  returned list. This is ADR-003's "partial results are normal" rule;
  don't treat it as a failure case.

Using it directly, e.g. in a test or for a small fixed option list:

```elixir
results = [
  %Flicker.Result{value: 1, label: "Casey Cassidy", sublabel: "Bass"},
  %Flicker.Result{value: 2, label: "Alex Rivers", sublabel: "Drums"}
]

<Flicker.select
  id="instrument-select"
  source={{Flicker.Providers.Static, results: results}}
  on_select={:result_selected}
/>
```

## Writing your own

Start from the same two callbacks:

```elixir
defmodule MyApp.Providers.Http do
  @behaviour Flicker.Provider

  @impl true
  def search(%Flicker.Query{text: text}, opts) do
    case MyApp.SearchApi.query(text, limit: opts[:limit]) do
      {:ok, records} ->
        {:ok, Enum.map(records, &to_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch(values, _opts) do
    case MyApp.SearchApi.fetch_many(values) do
      {:ok, records} -> {:ok, Enum.map(records, &to_result/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_result(record) do
    %Flicker.Result{value: record.id, label: record.name, sublabel: record.description}
  end
end
```

```heex
<Flicker.select id="global-search" source={MyApp.Providers.Http} actor={@current_user} on_select={:result_selected} />
```

A few rules to keep in mind:

- **Return `{:error, term}`, don't raise, for expected failure modes.**
  Core rendering code renders a themed error state on `{:error, _}` and
  never crashes on a provider error. `run_search/3`/`run_fetch/3` also
  catch unexpected exceptions and normalise them, but treat that as a
  safety net, not a substitute for handling errors your provider knows
  about.
- **Honour `:actor`/`:tenant` yourself if the source is
  authorization-aware.** Flicker passes them straight through in `opts`
  (ADR-004); a provider wrapping something like an internal permissions
  check needs to apply them the way `Flicker.Providers.AshResource` does
  for Ash — scoping every read, not just filtering the display.
- **`opts` is the merge of the provider's static config and the
  per-call options**, with per-call options taking precedence. A
  `{module, opts}` tuple's `opts` — e.g. `results:` above — arrives
  alongside `:actor`, `:tenant`, and `:limit` in the same keyword list.
- **Every returned struct must be a `Flicker.Result`.** A provider that
  returns anything else — a bare map, a raw Ash record — gets its result
  list rejected by `run_search/3`'s normalisation and surfaced as
  `{:error, {:invalid_provider_result, results}}`, not silently coerced.

For facet support, see the [faceted search guide](faceted-search.md#custom-providers) —
implementing `facets/0` lets a Tier 2 provider participate in
`Flicker.search/1` and facets-in-select the same way
`Flicker.Providers.AshResource.facets/1` does for Ash resources.
