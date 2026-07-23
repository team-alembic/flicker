<p align="center">
  <img src="https://raw.githubusercontent.com/team-alembic/flicker/main/assets/flicker-logo.png" alt="Flicker" width="240">
</p>

<h1 align="center">Flicker</h1>

<p align="center">
  <strong>Ash-native search, filtering, and record selection for Phoenix LiveView.</strong>
</p>

<p align="center">
  Searchable selects, multi-selects, faceted filter bars, and command palettes<br>
  backed directly by your data — no options plumbing required.
</p>

<p align="center">
  <a href="https://github.com/team-alembic/flicker/actions/workflows/elixir.yml"><img alt="CI" src="https://github.com/team-alembic/flicker/actions/workflows/elixir.yml/badge.svg"></a>
  <a href="https://github.com/team-alembic/flicker/blob/main/LICENSE"><img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue.svg"></a>
  <img alt="Elixir 1.17+" src="https://img.shields.io/badge/Elixir-1.17%2B-4B275F.svg">
  <img alt="Phoenix LiveView 1.1+" src="https://img.shields.io/badge/Phoenix%20LiveView-1.1%2B-F05423.svg">
  <img alt="Pre-release" src="https://img.shields.io/badge/status-pre--release-orange.svg">
</p>

Flicker is what [Cinder](https://hex.pm/packages/cinder) is for tables, but
for finding and picking records. Point it at an Ash resource, pass the actor,
and get an authorised typeahead without loading every record into a giant
`options` list.

> [!IMPORTANT]
> Flicker is under active development and has not been published to Hex yet.
> Install it from GitHub for evaluation. The public API may change before the
> first release.

## Why Flicker?

- **Your resource is the data source.** Give Flicker `resource`, `search`, and
  `option_label`; it builds and runs the Ash query itself.
- **Authorization stays in Ash.** `actor` and `tenant` flow through every
  search and fetch. Flicker adds no parallel permission system.
- **Small core, clean escape hatch.** Phoenix LiveView is the only hard
  runtime dependency. Ash support is optional, and any module implementing
  `Flicker.Provider` can search an API, cache, index, or several resources.
- **One interaction model, four surfaces.** Single-select, multi-select,
  standalone faceted search, and a full command palette share the same query,
  provider, result, theming, and keyboard machinery.
- **Built for production details.** Debounced async search, stale-result
  cancellation, batch resolution of existing values, reconnect-safe form
  inputs, windowed pagination, actor-scoped relationship facets, and
  user-facing error states are already covered.
- **Accessible by design.** Editable-combobox semantics, active-descendant
  keyboard navigation, polite live-region announcements, a palette focus
  trap, overridable copy, axe-core scans, and real-browser keyboard tests
  ship in the repository. Manual assistive-technology testing is still in
  progress; see [Accessibility](#accessibility).

## What ships today

| Surface | Use it for | Entry point |
|---|---|---|
| Searchable select | Pick one record in a form or controlled LiveView | `Flicker.select/1` |
| Multi-select | Pick many records with chips or custom selected-item UI | `Flicker.select/1` with `multiple` |
| Faceted search | Drive an Ash query, Cinder collection, stream, or list | `Flicker.search/1` |
| Command palette | Grouped global search with optional navigation | `Flicker.palette/1` |

The current implementation also includes:

- form-field and controlled modes;
- custom option and selected-item slots;
- avatar stacks with `max_visible` overflow;
- `min_chars`, debouncing, limits, base filters, sorting, and custom read actions;
- opt-in infinite scroll with capped result windows;
- Datadog-style facets such as `status:active after:7d rock`;
- type-derived enum, boolean, date, number, and relationship suggestions;
- removable facet pills in `Flicker.search/1`, including host-defined colour indicators;
- global keyboard activation such as `mod+k`;
- vanilla, Tailwind, and daisyUI theme presets;
- fully overridable visible text and screen-reader announcements;
- Cinder query and URL-state helpers;
- an AshPhoenix form adapter and PhoenixTest helper;
- an Igniter-powered installer; and
- an in-repository playground with copyable examples.

See the [spec index](https://github.com/team-alembic/flicker/blob/main/docs/specs/README.md) for shipped work, work in progress,
and deliberately deferred ideas. In particular, `Flicker.select/1` already
parses facets and filters its records, but committed facets remain raw input
text there; pill rendering inside selects is still a draft.

## Install

Until the first Hex release, add the GitHub dependency:

```elixir
def deps do
  [
    {:flicker, github: "team-alembic/flicker", branch: "main"},

    # Required only for the built-in Ash resource provider:
    {:ash, "~> 3.0"},
    {:ash_phoenix, "~> 2.0"}
  ]
end
```

Flicker requires Elixir 1.17 or later and Phoenix LiveView 1.1 or later.
Its JavaScript is delivered through LiveView's colocated-hook dependency
manifest.

If your project has [Igniter](https://hex.pm/packages/igniter), fetch the
dependency and run the included installer:

```bash
mix deps.get
mix flicker.install
```

It imports Flicker into the formatter, adds the default limit and debounce
configuration, and merges Flicker's colocated hooks into your `LiveSocket`.
For manual installation, follow the exact hook wiring in the
[getting-started guide](guides/getting-started.md#install).

## Pick a record

```heex
<Flicker.select
  id="client-select"
  field={@form[:client_id]}
  resource={MyApp.Client}
  actor={@current_user}
  search={[:first_name, :last_name, :uci_number]}
  option_label={:full_name}
  option_sublabel={fn client -> "#{client.uci_number} · #{client.city}" end}
  read_action={:search}
  limit={20}
/>
```

Pass a `Phoenix.HTML.FormField` for form mode, or replace `field` with an
`on_select` message name for controlled mode:

```heex
<Flicker.select
  id="global-search"
  source={MyApp.Search.Global}
  actor={@current_user}
  on_select={:result_selected}
/>
```

```elixir
def handle_info({:result_selected, result}, socket) do
  {:noreply, assign(socket, :selected, result)}
end
```

Exactly one of `field` or `on_select` is required.

## Pick many

The same component becomes a multi-select with `multiple`. Existing values
are resolved in one `fetch/2` call, form mode emits array inputs, and
controlled mode receives the complete selection list after every change.

```heex
<Flicker.select
  id="worker-select"
  field={@form[:worker_ids]}
  resource={MyApp.Worker}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  multiple
  max_selections={5}
/>
```

Use the `:selected` slot and `max_visible` for richer selected-item UI such
as an avatar stack with a `+N` overflow token.

## Filter with facets

`Flicker.search/1` has no selection semantics. It parses the input, renders
committed filters as removable pills, and sends the query plus its composed
Ash filter to your LiveView.

```heex
<Flicker.search
  id="artist-search"
  resource={MyApp.Artist}
  actor={@current_user}
  facets={[
    {:status, value_colors: %{active: "#16a34a"}},
    :genre,
    after: [attribute: :formed_on, op: :>=]
  ]}
  on_change={:artist_query_changed}
/>
```

```elixir
def handle_info({:artist_query_changed, _query, filter}, socket) do
  artists =
    MyApp.Artist
    |> Ash.Query.filter_input(filter)
    |> Ash.read!(actor: socket.assigns.current_user)

  {:noreply, assign(socket, :artists, artists)}
end
```

Distinct facet keys are ANDed; repeated values of the same facet are ORed.
Unknown keys and malformed values degrade to free text instead of breaking
the input. Read the [faceted-search guide](guides/faceted-search.md) for the
grammar and type-derived behavior.

## Open a command palette

```heex
<Flicker.palette
  id="cmdk"
  source={MyApp.Search.Global}
  actor={@current_user}
  open={@palette_open}
  on_close={:palette_closed}
  on_select={:palette_selected}
/>
```

The palette opens with Cmd+K on macOS or Ctrl+K elsewhere. Results carrying
a `group` render under group headings; a result with `meta.href` navigates
with `push_navigate/2` after selection. See the
[command-palette guide](guides/command-palette.md).

## Bring any data source

Implement two callbacks to use a non-Ash or federated backend:

```elixir
defmodule MyApp.Search.Global do
  @behaviour Flicker.Provider

  @impl true
  def search(%Flicker.Query{text: text}, opts) do
    MyApp.SearchIndex.search(text,
      actor: opts[:actor],
      tenant: opts[:tenant],
      limit: opts[:limit]
    )
  end

  @impl true
  def fetch(values, opts) do
    MyApp.SearchIndex.fetch_many(values,
      actor: opts[:actor],
      tenant: opts[:tenant]
    )
  end
end
```

Both callbacks return `{:ok, [%Flicker.Result{}]}` or `{:error, reason}`.
Optional `facets/0` and `render_option/2` callbacks extend the surface. The
[provider guide](guides/providers.md) documents the complete contract,
pagination offset, and reference static provider.

## Make it yours

Flicker uses a class-per-part `%Flicker.Theme{}` rather than owning your CSS
framework:

```elixir
config :flicker, default_theme: Flicker.Theme.tailwind()
```

```heex
<Flicker.select
  theme={%{search_input: "my-input", option_active: "my-active-option"}}
  ...
/>
```

Choose `Flicker.Theme.vanilla/0`, `tailwind/0`, or `daisy_ui/0`; replace a
whole theme or merge only the parts you need. The
[theming guide](guides/theming.md) contains the full part map.

Every visible string and live announcement goes through
`Flicker.Messages`. Override the module globally or per component for
localization and product voice without forking component markup.

## Accessibility

Flicker implements WAI-ARIA editable-combobox behavior, keeps DOM focus on
the input while moving `aria-activedescendant`, announces loading/results/
selection/error changes, supports the full keyboard map, and traps/restores
focus in the command palette.

CI exercises axe-core against every playground route and drives the
client-side keyboard behavior through Chrome. The remaining pre-1.0
accessibility work is the manual VoiceOver, NVDA, and JAWS matrix tracked in
[Spec 007](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-007-screen-reader-support.md). Read the
[accessibility statement and manual test script](guides/accessibility.md).

## Playground

The repository includes a database-free Phoenix app backed by seeded Ash ETS
resources:

```bash
mix deps.get
mix dev
```

Visit `http://localhost:4000` for live, copyable examples of the selection
modes, custom slots, facets, pagination, keyboard activation, palette,
themes, providers, Cinder integration, localization, and error states.

## Development

Tool versions are pinned in [`.tool-versions`](https://github.com/team-alembic/flicker/blob/main/.tool-versions). The main
quality gate covers formatting, Credo, documentation coverage, Sobelow,
dependency audits, Dialyzer, and ExUnit:

```bash
mix deps.get
mix check
```

The real-browser suite is separate because it requires Chrome and
`chromedriver`:

```bash
mix test --only browser
```

Architecture and sequencing live in [the design document](https://github.com/team-alembic/flicker/blob/main/docs/DESIGN.md);
feature contracts live in [specs](https://github.com/team-alembic/flicker/blob/main/docs/specs/README.md); structural decisions
live in [ADRs](https://github.com/team-alembic/flicker/blob/main/docs/adrs/README.md). Contributions should follow
[AGENTS.md](https://github.com/team-alembic/flicker/blob/main/AGENTS.md).

## License

Flicker is released under the [Apache License 2.0](https://github.com/team-alembic/flicker/blob/main/LICENSE).
