---
status: draft # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, adr-006, adr-009, adr-011, adr-012, adr-013]
---

# Spec 018: Rich facet types — range/list grammar, type derivation, and value validation

Spec 003 derives facet behaviour from six types (`:string`, `:integer`,
`:float`, `:boolean`, `:date`, `:enum`), each of which casts a single scalar
value. That's enough to filter, but not enough to build a *good* control on:
"created between two dates", "price between two numbers", and "status is any
of these three" have no grammar today, and a value that won't cast is silently
swallowed. This spec adds the pure core those controls need — the types, the
range and list grammar, the Ash derivation that fills in bounds and presets,
and per-facet value validation with real reasons — with **no rendering**. The
editors that consume it are Spec 019.

Everything here is a pure function over strings and facet structs, testable
with unit and property tests and no browser.

## Scope

### `Flicker.Facet` — new types and fields

`Facet.type` gains:

| Type | Meaning | Default operators | Default op for `:` |
|---|---|---|---|
| `:date_range` | a closed or half-open date interval | `[:between]` | `:between` |
| `:datetime` | an instant, UTC | `[:eq, :neq, :gt, :gte, :lt, :lte]` | `:eq` |
| `:datetime_range` | a UTC instant interval | `[:between]` | `:between` |
| `:number_range` | a numeric interval | `[:between]` | `:between` |
| `:duration` | an elapsed time, cast to integer seconds | `[:eq, :neq, :gt, :gte, :lt, :lte]` | `:eq` |

`Facet.operator` gains `:between`, `:in`, and `:not_in`.

New `Facet` fields, all optional and all consumed by Spec 019's editors:

- `:scalar` — for the three range types, the type of each endpoint:
  `:date`, `:datetime`, `:integer`, or `:float`. Defaults from the range
  type (`:date_range` → `:date`, `:datetime_range` → `:datetime`,
  `:number_range` → `:integer`), and is set explicitly by the Ash derivation
  when it sees a float/decimal attribute. `nil` for non-range types.
- `:bounds` — `%{min: number(), max: number(), step: number()}`, any key
  optional. Derived from an Ash attribute's `min`/`max` constraints. Purely
  advisory to editors (a slider needs endpoints); also used by validation to
  reject out-of-bounds values. `nil` when unbounded.
- `:presets` — for the date/datetime range types, an ordered list of
  `%Flicker.Facet.Preset{}` (see below). Defaults to a built-in list;
  overridable per facet.
- `:suggested` — a subset of `:presets` ids to surface first. `nil` for none.
- `:multiple?` — `true` lets an `:enum` or relationship facet take a
  comma-separated list (`:in`/`:not_in`). Defaults to `false`, so existing
  single-value behaviour and its `:eq` tuples are unchanged.
- `:validate` — an optional extra validator, `(term() -> :ok | {:error,
  {atom(), map()}} | {:error, String.t()})`, run *after* the type's own cast
  succeeds and given the cast value. Independent of the type: a host can
  reject a date range longer than a year, or a price range whose span is
  absurd, without inventing a type. A bare string error becomes
  `{:custom, %{message: string}}`.
- `:editor` — a module implementing Spec 019's editor behaviour, overriding
  the type's default editor. `nil` uses the default. Declared here so the
  derivation and `resolve_facets/1` can carry it; unused until Spec 019.

### `Flicker.Facet.value_source/1`

Per [ADR-011](../adrs/adr-011-facet-editors-are-modal-subcontexts.md), a
set-valued facet is edited by a nested `Flicker.select`, and the only thing
that differs between an enum facet and a relationship facet is the provider
behind it. This spec provides the accessor that erases that difference:

```elixir
@spec value_source(t()) :: {module(), keyword()} | nil

# :enum — the closed set, as a Static provider
value_source(%Facet{type: :enum, values: [:active, :inactive], value_labels: labels})
#=> {Flicker.Providers.Static, results: [
#     %Flicker.Result{value: :active, label: "Active"},
#     %Flicker.Result{value: :inactive, label: "Inactive"}
#   ]}

# relationship — the related resource, as it is built today
value_source(%Facet{key: :worker, related: %{resource: Worker, search: [:full_name], ...}})
#=> {Flicker.Providers.AshResource, resource: Worker, search: [:full_name], option_label: ...}

# :boolean — the fixed pair
value_source(%Facet{type: :boolean})
#=> {Flicker.Providers.Static, results: [%Result{value: true, label: "true"}, ...]}

# anything else
value_source(%Facet{type: :date_range})  #=> nil
```

**`value_source/1` is about candidate values, not about controls.** It answers
"what can this facet's value be", which is what typeahead in the plain input
needs — and `Flicker.FacetSuggest` already suggests `true`/`false` for boolean
facets today, so `:boolean` belongs here. Which *editor* opens for a type is a
separate mapping, defined in Spec 019: `:enum` and relationship facets get the
nested `Flicker.select`, but `:boolean` gets a **switch**, and it never touches
`value_source/1`. Two facets can share a source and not share an editor.

Labels come from `:value_labels` (an `Ash.Type.Enum`'s own `label/1`, or the
humanised fallback Spec 012 already defines), so a `Static`-backed enum editor
displays `Established`, not `established`, and Spec 017's `:value_colors` key
off the same value atoms with no extra plumbing.

`Flicker.FacetSuggest`'s existing suggestion functions are refactored onto
this: `enum_value_suggestions/2` and `related_search/3` become one code path
that runs `Flicker.Provider.run_search/3` against `value_source/1` and maps
the results to suggestions. The public functions stay (they're documented
API), the duplication doesn't. The Ash-only compile guard moves to
`value_source/1`'s relationship clause — without `ash`, an enum facet's
`Static` source still works, matching [ADR-006](../adrs/adr-006-core-depends-only-on-provider.md).

This is what makes Spec 019's set editor a single component rather than two:
it renders a `Flicker.select` with `source: Facet.value_source(facet)`,
`multiple: facet.multiple?`, in controlled mode, with no facets of its own.

### `Flicker.Facet.Range`

The cast value of every range type:

```elixir
%Flicker.Facet.Range{
  from: term() | nil,   # cast per the facet's :scalar; nil = open lower bound
  to: term() | nil,     # nil = open upper bound
  preset: atom() | nil  # the preset id this range came from, if any
}
```

`:preset` is why this is a struct rather than a tuple: it is what lets a pill
read `Last 30 days` instead of a resolved pair of dates, and it is what
`Flicker.Query.input` round-trips (see [ADR-011](../adrs/adr-011-facet-editors-are-modal-subcontexts.md)
— presets serialise as their id, so a shared query stays relative). Both
`:from` and `:to` are `nil` only for the `all-time` preset.

### `Flicker.Facet.Preset`

```elixir
%Flicker.Facet.Preset{
  id: atom(),                              # serialised form, e.g. :last_30_days
  token: String.t(),                       # typed form, e.g. "last-30-days"
  label: String.t(),                       # display, e.g. "Last 30 days"
  resolve: (Date.t() -> {Date.t() | nil, Date.t() | nil})
}
```

`:resolve` takes "today" as an argument rather than calling `Date.utc_today/0`
itself, so every preset is a pure function and the whole set is testable at a
fixed date. The built-in list, resolved against a reference date:

`today`, `yesterday`, `last-7-days`, `last-30-days`, `last-60-days`,
`last-90-days`, `this-week`, `last-week`, `this-month`, `last-month`,
`in-the-last-month`, `this-quarter`, `year-to-date`, `all-time`.

`all-time` resolves to `{nil, nil}`.

Week-sensitive presets (`this-week`, `last-week`) use **the locale's own first
day of week** (`Localize.Calendar`), not a hardcoded Monday — Sunday in the US,
Saturday across much of MENA (ADR-013). `:resolve` therefore takes the
reference date plus the first-day-of-week as arguments rather than reaching for
either; without `localize` it falls back to Monday, matching ISO 8601.

Preset **ids are canonical** and their resolution is contextual: `last-week`
always serialises as `last-week`, and resolves against both the reference date
and the locale's week rules. That is the same property that makes
`last-30-days` mean something different tomorrow, and it is the reason presets
serialise as ids rather than as resolved dates.

### Grammar additions

Two literals, both per-token, both preserving Spec 003's rule that a token
which fails to match degrades or is reported as a whole:

**Range literal** — `from..to`, `..to`, `from..`, where each endpoint casts
per the facet's `:scalar`. Accepted only on a range-typed facet, and only with
`:` (mapped to `:between`). A bare `..` is not a range. Range facets also
accept a **single scalar** (`created:2026-07-01`), which casts to
`%Range{from: d, to: d}` — a one-day range for `:date_range`, and for
`:datetime_range` the whole UTC day (`00:00:00Z` to `23:59:59.999999Z`).

**Preset literal** — on a date/datetime range facet, a bare token matching a
preset's `:token` casts to that preset's resolved range with `:preset` set.
Preset tokens are matched before the range literal, and case-sensitively.

**List literal** — `a,b,c` on a facet with `multiple?: true`. `:` maps to
`:in`, `!=` to `:not_in`. Commas inside a quoted span are literal, so
`worker:"Nguyen, Casey"` is one value. A single element with no comma keeps
the scalar operators (`:eq`/`:neq`) so existing parses are untouched. Empty
elements (`a,,b`, `a,`) are invalid, not free text — which is exactly the
mid-typing state, and per
[ADR-012](../adrs/adr-012-parse-reports-invalid-facet-tokens.md) it reports
rather than degrading.

**Relative and named dates** — `:date` and `:datetime` gain `today` and
`yesterday` alongside Spec 003's existing `Nd`/`Nw`/`Nm`/`Ny` offsets.

**Datetime literals** — full ISO 8601 with an explicit `Z` offset
(`2026-07-01T09:30:00Z`), or a bare date meaning midnight UTC.

### `Flicker.Query`

- New field `:invalid` — `[%Flicker.Query.Invalid{}]`, per ADR-012:

  ```elixir
  %Flicker.Query.Invalid{
    key: atom(),
    operator: Facet.operator(),
    raw: String.t(),      # the value as typed
    token: String.t(),    # the whole token as typed
    reason: atom(),
    params: map()
  }
  ```

- `Flicker.Query.valid?/1` — `invalid == []`.

**Validation is per-facet and independent.** A broken token invalidates
*itself* and nothing else: the other facets still filter, the free text still
searches, and `to_filter/2` still emits every valid clause. `status:activ
price:10..50` runs the price filter and reports the status typo — it does not
withhold the whole query. That is the point of `:invalid` being a list keyed by
token rather than a single query-level flag, and it means a facet the user is
still typing never freezes the results they already have.

`valid?/1` is therefore a *query-level convenience*, not the dispatch gate. The
gate is per-token: an invalid token contributes no filter clause and renders as
an error (Spec 012's pill, Spec 019's editor), while the query built from
everything else dispatches normally. The cost is that results can be broader
than the user's typed intent while one facet is broken, which is why the error
state has to be conspicuous and announced (Spec 007) rather than a quiet outline
— an invisible error plus a silently wider result set is the failure mode to
design against.
- `to_filter/2` expands the new operators: `:between` to
  `%{"and" => [%{"gte" => from}, %{"lte" => to}]}` (dropping the clause for a
  `nil` endpoint, so `10..` is a lone `gte`, and `all-time` contributes no
  clause at all), `:in` to `%{"in" => values}`, `:not_in` to
  `%{"not" => %{"in" => values}}`.

### `Flicker.Facet.validate_value/2`

`validate_value(facet, raw) :: :ok | {:error, {reason :: atom(), params :: map()}}`
— the single place a raw value string is judged, called by the parser and
(Spec 019) by editors before they commit. Reasons and their params:

| Reason | Raised when |
|---|---|
| `:bad_integer` / `:bad_float` | won't parse as a number |
| `:bad_boolean` | not `true`/`false`, case-insensitive |
| `:bad_date` / `:bad_datetime` | not ISO 8601, a known relative offset, or a named date |
| `:bad_duration` | not a duration expression |
| `:bad_range` | not a range, preset, or bare scalar |
| `:incomplete_range` | `..` with neither endpoint |
| `:reversed_range` | `from` is after `to` |
| `:not_in_values` | `%{values: [atom()]}` — enum value outside the closed set |
| `:incomplete_list` | an empty element in a list literal |
| `:out_of_bounds` | `%{min:, max:}` — outside the facet's `:bounds` |
| `:constraint_violation` | `%{message: String.t()}` — from `Ash.Type.apply_constraints/2` |
| `:custom` | `%{message: String.t()}` — from the facet's own `:validate` |

Every reason gets a `Flicker.Messages` callback (ADR-009), covered the way
`Flicker.ThemeTest` covers theme parts: a test enumerates the reason list and
asserts the messages module answers for each.

### `Flicker.Facet.Format` — localised display

Per [ADR-013](../adrs/adr-013-canonical-tokens-localised-display.md), token
text is locale-invariant and localisation is a display layer. This spec adds
the one module every display path goes through, so the with/without-`localize`
fallback lives in a single place:

```elixir
@spec value_label(Facet.t(), term(), keyword()) :: String.t()
# opts: [locale: Localize.LanguageTag.t() | String.t() | nil]
```

| Facet value | With `localize` | Fallback |
|---|---|---|
| `%Range{from: d1, to: d2}` (dates) | `Localize.Interval.to_string/3` — CLDR-collapsed (`Jun 18 – Jul 12`) | `"2026-06-18 – 2026-07-12"` |
| `%Range{preset: id}` | the preset's CLDR label (`Localize.DateTime.Relative`) | the preset's `:label` |
| `%Range{}` (numeric) | `Localize.Number.to_string/2` per endpoint | `to_string/1` |
| integer / float | `Localize.Number.to_string/2` | `to_string/1` |
| duration (seconds) | `Localize.Duration.to_string/2` — plural-aware (`2 hr 30 min`) | `"2h30m"` |
| `:date` / `:datetime` | `Localize.Date`/`DateTime.to_string/2` | ISO 8601 |
| a list (`:in`) | `Localize.List.to_string/1` — locale conjunction | `Enum.join(", ")` |
| enum / boolean | `:value_labels`, unchanged | same |

Two more localisation touch points:

- `value_source/1`'s `Static` results are ordered with
  `Localize.Collation.sort/1` when available, so a value list sorts by the
  locale's rules rather than by codepoint.
- Validation reasons (ADR-012) render through `Flicker.Messages`, which gains
  `Localize.Message.format/3` (ICU MessageFormat 2) as an optional backend —
  plural-aware messages, no new seam beyond the one
  [ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md) already
  defines.

`localize` is `optional: true` and guarded with `Code.ensure_loaded?(Localize)`,
exactly as `ash` is. Locale is passed explicitly (defaulting to
`Localize.get_locale/0`) rather than read from process state at the point of
formatting — see ADR-013 on why.

### Ash derivation (`Flicker.Providers.AshResource.facets/1`)

Additions to the existing type table:

- `Ash.Type.UtcDatetime` / `NaiveDatetime` → `:datetime`.
- `min`/`max` constraints on an integer/float/decimal attribute → `:bounds`,
  with `:step` left unset (an editor's own default).
- `Ash.Type.Decimal` → `:float` (or `:number_range` with `scalar: :float`);
  the filter value is a float, which is a documented precision trade-off for
  filtering, not for storage.
- The range types are **not** auto-derived — a `:date` attribute derives a
  `:date` facet, because "created on" and "created between" are different
  questions and only the host knows which it wants. Range behaviour is an
  explicit override: `facets: [created_at: [type: :date_range]]`. The
  derivation still fills in `:scalar`, `:presets`, and `:bounds` from the
  attribute once asked.
- `multiple?: true` is likewise an opt-in override on an enum or relationship
  facet.

## Non-goals

- **No rendering, no editors, no focus behaviour.** The editor behaviour, the
  calendar, the slider, the pop-out and its keyboard model are Spec 019; this
  spec only provides the data they read and the text they emit.
- **No localised parsing.** Per ADR-013 the grammar is locale-invariant: ISO
  8601 dates, `.` as the decimal separator, canonical preset and enum ids.
  `parse/2` takes no locale argument. Locale-native *input* is a rich-editor
  concern (Spec 019), and editors serialise back to canonical tokens.
- **No timezone handling.** Datetimes are UTC only: an explicit `Z` offset is
  required on a full literal, a bare date means midnight UTC, and nothing is
  converted to an actor's or the app's zone. Actor-relative zones are a
  follow-up (see Open questions).
- **No query-dispatch mode.** Whether a query fires per keystroke or only on
  `Enter` is a separate concern from facet types (it applies to plain free
  text too) and is proposed as its own small spec.
- **No new grammar for open-ended future dates** (`+7d`), set algebra, or
  geographic/distance types.
- **No duration ranges.** `:duration` with `>=`/`<=` covers the useful cases;
  `:duration_range` can follow if asked for.
- **No change to Spec 003's degrade-to-free-text rule for unknown keys** —
  only the known-facet-bad-value case changes, per ADR-012.

## Design

The parser's existing per-token pipeline gains one step and one branch. Today
`Flicker.Query.classify/2` runs `key → facet → operator → value → cast`, and
any `:error` falls to `{:text, token}`. It becomes:

```elixir
defp classify(token, facet_index) do
  with [_, key_str, op_str, rest] <- Regex.run(@facet_token, token),
       {:ok, key} <- existing_atom(key_str),
       {:ok, facet} <- Map.fetch(facet_index, key),
       {:ok, op} <- resolve_operator(op_str, facet),
       {:ok, raw} <- extract_value(rest) do
    # Key and operator are both known-good from here: a bad value is
    # reported, never degraded (ADR-012).
    case Flicker.Facet.cast_value(facet, raw, op) do
      {:ok, op, value} -> {:facet, key, op, value}
      {:error, {reason, params}} -> {:invalid, key, op, raw, token, reason, params}
    end
  else
    _ -> {:text, freetext(token)}
  end
end
```

`Facet.cast_value/3` returns the operator alongside the value because casting
can *refine* it: `:` on a range facet resolves to `:between`, and on a
`multiple?: true` facet resolves to `:in` or `:eq` depending on whether the
literal has commas. It is `validate_value/2`'s successful sibling — one
implementation, two return shapes — so a reason can never exist without the
cast rejecting the value that produces it, and vice versa.

Casting a range endpoint delegates to the scalar cast for `facet.scalar`, so
the date grammar (ISO, relative, named) exists in exactly one place and
`created:7d..today` works without a special case.

`Flicker.CursorContext` needs no structural change — it already returns
`{:value, facet, prefix}` for a mid-type value and deliberately does not cast.
Two additions for Spec 019's benefit: the classification reports which
*endpoint* of a range literal the caret sits in (before or after the `..`),
and which element of a list literal, so an editor can open focused on the
right control.

`Flicker.FacetSuggest.enum_value_suggestions/2` gains a preset clause for
date/datetime range facets — the preset tokens filtered by prefix — which
means presets are typeahead-completable in the plain input with no editor at
all, and Spec 019's rail is a nicer skin over the same list.

### Worked examples

```elixir
facets = [
  %Facet{key: :created, type: :date_range, scalar: :date},
  %Facet{key: :price, type: :number_range, scalar: :integer, bounds: %{min: 0, max: 500}},
  %Facet{key: :status, type: :enum, values: [:active, :inactive], multiple?: true}
]

Query.parse("created:last-30-days", facets)
#=> facets: [{:created, :between, %Range{from: ~D[2026-06-29], to: ~D[2026-07-28], preset: :last_30_days}}]

Query.parse("price:10..50 status:active,inactive", facets)
#=> facets: [
#     {:price, :between, %Range{from: 10, to: 50}},
#     {:status, :in, [:active, :inactive]}
#   ]

Query.parse("price:10..", facets) |> Query.to_filter(facets)
#=> %{"price" => %{"gte" => 10}}

Query.parse("price:50..10", facets)
#=> invalid: [%Invalid{key: :price, reason: :reversed_range, params: %{from: 50, to: 10}}]
#   text: ""   # never free text (ADR-012)

Query.parse("price:900", facets)
#=> invalid: [%Invalid{key: :price, reason: :out_of_bounds, params: %{min: 0, max: 500}}]

Query.parse("nonsense:900", facets)
#=> text: "nonsense:900"   # unknown key still degrades (Spec 003)
```

## Acceptance criteria

Grammar and casting:

- [ ] `created:2026-06-01..2026-06-30` parses to a `:between` match with both
      endpoints set; `created:..2026-06-30` and `created:2026-06-01..` each set
      one endpoint and leave the other `nil`.
- [ ] `created:2026-07-01` on a `:date_range` facet parses to a single-day
      range; the same token on a `:datetime_range` facet spans that whole UTC
      day.
- [ ] Every built-in preset token parses to the range its `:resolve` produces
      for a fixed reference date, with `:preset` set to its id, and
      `all-time` produces `{nil, nil}` and contributes no `to_filter` clause.
- [ ] `this-week` and `last-week` resolve to different ranges for `en-US`
      (Sunday start) and `en-AU` (Monday start) at the same reference date, and
      fall back to Monday without `localize`.
- [ ] `status:active,inactive` on a `multiple?: true` enum parses to a single
      `:in` match with both atoms; `status!=active,inactive` to `:not_in`.
- [ ] `status:active` on a `multiple?: true` facet still parses to `:eq` with a
      bare atom — no list wrapping.
- [ ] `worker:"Nguyen, Casey"` is one value; the comma is not a separator.
- [ ] `created:7d..today` parses — relative and named dates work as range
      endpoints.
- [ ] `2h30m`, `15m`, `90s`, `1d` cast to the right integer seconds on a
      `:duration` facet.
- [ ] Every doctest and test in the existing Spec 003 suite still passes
      unchanged, except those asserting that a known facet's bad value lands in
      `:text`.

Validation:

- [ ] Each reason in the table is produced by at least one input, with its
      documented params.
- [ ] A reported token appears in `:invalid` and in neither `:facets` nor
      `:text`; `valid?/1` is `false`.
- [ ] `nonsense:900` and `hello: world` are still free text with an empty
      `:invalid`.
- [ ] A facet whose target attribute has `min`/`max`/`match` constraints
      reports `:constraint_violation` with Ash's own message for a violating
      value.
- [ ] `Flicker.Messages` answers for every reason atom, enforced by a test
      that enumerates the list rather than hardcoding it.
- [ ] `parse/2` never raises for any input: a property test over arbitrary
      binaries and the full facet-type matrix.
- [ ] `status:activ price:10..50` reports only the status token and still
      parses the price facet; `to_filter/2` on that query emits the price
      clause and nothing for status.
- [ ] Two broken tokens produce two independent `:invalid` entries, each with
      its own reason.
- [ ] A facet's `:validate` runs only after a successful cast, receives the
      cast value, and a string error surfaces as `{:custom, %{message: ...}}`.
- [ ] A facet with no `:validate` behaves identically to one before the field
      existed.

Filters and derivation:

- [ ] `to_filter/2` emits the documented shapes for `:between` (both, and each
      half-open form), `:in`, and `:not_in`, and resolves them through a
      relationship path the same way `:eq` does.
- [ ] Repeated instances of the same range facet still OR together, per Spec
      003.
- [ ] A `:utc_datetime` attribute derives a `:datetime` facet; `type:
      :date_range` as an override on a `:date` attribute derives `:scalar`,
      `:presets`, and (where constrained) `:bounds`.
- [ ] A `:date` attribute with no override still derives a plain `:date`
      facet — range behaviour is never assumed.
- [ ] An integer attribute with `constraints: [min: 0, max: 500]` derives
      `bounds: %{min: 0, max: 500}`.
- [ ] Every new field has a default that leaves a hand-built
      `%Flicker.Facet{key: :x}` behaving exactly as it does today.

Value sources:

- [ ] `value_source/1` returns a `Static` provider for `:enum` and `:boolean`
      facets, an `AshResource` provider for a relationship facet, and `nil`
      for every other type.
- [ ] A `Static`-backed enum source carries `:value_labels` labels, so
      searching it by label (`Estab`) matches the value whose atom is
      `:established`.
- [ ] `enum_value_suggestions/2` and `related_search/3` return exactly what
      they return today, now via one shared `run_search/3` path — their
      existing Spec 003 tests pass unchanged.
- [ ] With `ash` absent, an enum facet's `value_source/1` still works and a
      relationship facet's returns `nil` rather than failing to compile.

Localisation:

- [ ] `parse/2`'s arity and behaviour are unchanged by this section — no locale
      argument, and the same token produces the same filter under every locale
      (except the documented week-sensitive presets).
- [ ] A date `%Range{}` renders CLDR-collapsed for `en-AU`, `en-US`, and `de-DE`
      and differs between them; the same value renders as an ISO pair without
      `localize`.
- [ ] A multi-value `:in` list renders with the locale's conjunction (`and` /
      `und`) and as a plain comma join in the fallback.
- [ ] A duration renders plural-aware per locale and as `2h30m` in the fallback.
- [ ] `Flicker.Facet.Format.value_label/3` is the only module calling
      `Localize.*` for display — enforced by a test asserting no other module
      references it.
- [ ] The whole suite passes with `localize` absent, in its own CI matrix cell
      alongside the existing no-ash cell.

## Open questions

None blocking.

- **Actor-relative timezones for `:datetime`.** UTC-only for now (a deliberate
  scope cut). The likely shape is a facet-level `:time_zone` — an explicit
  zone, or a function of the actor — resolved at cast time, which needs a
  `tz` database decision and probably its own ADR.
- **Decimal precision.** Casting `Ash.Type.Decimal` to a float is fine for
  filtering and wrong for money arithmetic. If a host needs exact decimal
  filters, `:scalar` could gain `:decimal` and carry `Decimal` structs into
  the filter; deferred until someone wants it.
- **`!=` on a list.** `:not_in` is the obvious reading, but "not any of" vs
  "not all of" is arguable. Going with "not any of" (`not in`); revisit if it
  surprises anyone.
- **Locale-tolerant typed input.** Deliberately excluded (ADR-013), but it is
  the obvious future ask: accept `1.234,56` or `18/06/2026` in the main input
  and normalise on commit. Needs a locale argument on `parse/2` and an
  ambiguity rule for `06/18`; revisit if editors turn out not to cover it.
- **Preset ids vs tokens.** Carrying both (`:last_30_days` and
  `"last-30-days"`) is redundant, but an atom key reads better in host config
  than a hyphenated string, and the token is what appears in a URL. Could
  collapse to one if the duplication grates.
