# Faceted search

`Flicker.search/1` is the standalone filter bar: Datadog-style typed
input — `status:active worker:"Casey Nguyen" after:7d free text` — parsed
into a structured query and handed to your own list, table, or Cinder
collection. Unlike `Flicker.select/1`, it has no selection semantics: it
never lists or fetches records itself, it only emits what was typed.
Facets can also layer onto `Flicker.select/1` and `Flicker.palette/1` to
narrow the free-text portion of those pickers the same way.

## The filter bar

```heex
<Flicker.search
  id="artist-search"
  resource={Dev.Music.Artist}
  actor={@current_user}
  facets={[:status, :tier, :monthly_listeners, after: [attribute: :formed_on, op: :>=]]}
  on_change={:artist_query_changed}
/>
```

```elixir
def handle_info({:artist_query_changed, _query, filter}, socket) do
  artists =
    Dev.Music.Artist
    |> Ash.Query.filter_input(filter)
    |> Ash.read!(actor: socket.assigns.current_user)

  {:noreply, assign(socket, :artists, artists)}
end
```

The host's `handle_info/2` receives `{on_change, %Flicker.Query{}, filter}`
on every keystroke — `filter` is already the plain map
`Ash.Query.filter_input/2` expects, built by `Flicker.Query.to_filter/2`.
Feed it straight to your own `Ash.read/2` call, a stream, or a
[Cinder](cinder-integration.md) collection's `query` attr.

## Defining facets

`facets` is a list of bare keys and `{key, overrides}` pairs. Passed
alongside `resource`, each key is expanded by introspecting the resource's
own Ash type system (`Flicker.Providers.AshResource.facets/1`) — the facet
registry:

- an `Ash.Type.Enum` (or a `one_of`-constrained attribute) derives
  `type: :enum`, `:eq`-only, and a value picklist from `:values`;
- `:boolean` derives `type: :boolean`, `:eq`-only;
- a date/datetime attribute derives `type: :date`, operators `:eq` `:gte`
  `:lt` — `after:7d`, `after:2w`, `after:2024-01-01` all parse;
- `:integer`/`:decimal`/`:float` derive a numeric type with the full
  comparison operator set (`>`, `>=`, `<`, `<=`, `!=`, `:`);
- a `belongs_to`/`has_*` relationship derives a facet over the related
  record's id, with a nested actor-scoped search over the related
  resource — typing `worker:"Casey"` opens autocomplete against
  `Dev.Music.Worker` (or whatever the relationship points to) and inserts
  `worker:<id>`, displayed as the related record's own label while
  choosing;
- anything else derives `type: :string`, `:contains`-only free `ilike`.

`overrides` lets you redirect or override what's derived:

```elixir
facets={[
  :status,                                   # bare key, fully derived
  :tier,
  after: [attribute: :formed_on, op: :>=],   # alias `after` to the `formed_on` attribute, default op `>=`
  worker_name: [path: [:worker, :full_name]] # facet over a relationship path
]}
```

`:path` (a relationship path ending in an attribute), `:attribute` /
`:aggregate` (an explicit field name when it differs from the facet key),
`:type`, and `:op` (the default operator for the bare `key:value` form)
are all available as overrides. See `Flicker.Providers.AshResource.facets/1`'s
`@doc` for the exact derivation rules.

## Grammar

Typed input is tokenised on whitespace, except inside a double-quoted
span (`worker:"Casey Nguyen"` is one token). A token matches a facet when
it's `key<op>value` for a recognised key and a legal operator for that
facet's `:type`:

| Operator | Syntax | Meaning |
|---|---|---|
| `:eq` (bare) | `status:active` | equals |
| `:gte` | `after>=7d` | greater than or equal |
| `:lte` | `budget<=1000` | less than or equal |
| `:gt` | `count>5` | greater than |
| `:lt` | `formed<1980-01-01` | less than |
| `:neq` | `status!=inactive` | not equal |
| `:contains` | (string default) | substring match |

Anything that doesn't parse as a recognised `key<op>value` — an unknown
key, a malformed operator, a value that doesn't cast to the facet's
`:type` (e.g. `tier:legendaryyy` against an enum) — degrades to free
text rather than erroring. `Flicker.Query.parse/2` is a pure function
that never raises: arbitrary typing (unterminated quotes, stray
backslashes, mid-token unicode) always produces *some* valid
`%Flicker.Query{}`.

Repeating the same facet key ORs the instances together:
`status:active status:pending` matches either; distinct facet keys AND
together: `status:active tier:legendary` matches both.

## Facets on `Flicker.select/1`

The same `facets` attr narrows the free-text portion of a pick-one/pick-many
combobox — useful when the picker's own field list
(`search={[:first_name, :last_name]}`) isn't precise enough and you want
`status:active` to scope the candidates before the text match runs:

```heex
<Flicker.select
  id="artist-select"
  field={@form[:artist_id]}
  resource={Dev.Music.Artist}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  facets={[:status, :tier]}
/>
```

## Custom providers {: #custom-providers}

A Tier 2 `Flicker.Provider` (see the [providers guide](providers.md))
participates in faceted search by implementing the optional `facets/0`
callback, returning a hand-built list of `Flicker.Facet` structs instead
of relying on Ash introspection:

```elixir
@impl true
def facets do
  [
    %Flicker.Facet{key: :status, type: :enum, values: [:active, :inactive], operators: [:eq]},
    %Flicker.Facet{key: :created, type: :date, operators: [:eq, :gte, :lt], default_op: :gte}
  ]
end
```

Pass a hand-built list directly as `facets` (bypassing a provider's
`facets/0` entirely) when the facet set doesn't map onto any single Ash
resource:

```heex
<Flicker.search
  id="log-search"
  source={MyApp.Providers.Logs}
  facets={[%Flicker.Facet{key: :level, type: :enum, values: [:info, :warn, :error]}]}
  on_change={:log_query_changed}
/>
```

## See also

- `Flicker.Query` — the parsed query struct, grammar reference, and
  `to_filter/2`.
- `Flicker.Facet` — the facet definition struct.
- [Cinder integration](cinder-integration.md) — pairing `Flicker.search`
  with a Cinder table.
