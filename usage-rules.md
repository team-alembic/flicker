# Rules for working with Flicker

<!--
  This file is published to Hex alongside the package and is consumed by
  downstream AI agents via `mix usage_rules.sync`. Keep it focused on how to
  USE this package. Developer-facing rules belong in AGENTS.md.
-->

## Understanding Flicker

Flicker is an Ash-native searchable select / combobox / faceted-search
library for Phoenix LiveView. It reads directly off an Ash resource (or
any `Flicker.Provider`) — no options plumbing, no host web module.
`Flicker.select/1` (pick-one/pick-many) and `Flicker.search/1` (a
standalone faceted filter bar, no selection semantics) are the public
entry points; their backing `Phoenix.LiveComponent`s are private
implementation details.

## Core concepts

- **`Flicker.select/1`** — the function component. Tier 1: pass
  `resource` + `search` (field list) + `option_label` for the common
  case — Flicker compiles this to the built-in `Flicker.Providers.AshResource`
  provider. Tier 2: pass `source` (a module, or `{module, opts}`)
  implementing `Flicker.Provider` yourself for custom or federated search.
- **Modes** — exactly one of `field` (form-field mode: the component owns
  its hidden input and `_unused_` recovery marker) or `on_select` (an
  atom; controlled mode: your `handle_info/2` gets
  `{on_select, %Flicker.Result{} | nil}`) is required.
- **`actor`** — always pass it. It's the only authorization boundary:
  Flicker has no separate permission system, it relies entirely on Ash
  policies evaluated against the `actor` you give it. Omitting it means
  every read runs as `nil` actor.
- **`Flicker.Theme`** — a class-per-part styling map. Presets:
  `vanilla/0` (default), `tailwind/0`, `daisy_ui/0`. Override globally via
  `config :flicker, default_theme:` or per-component via the `theme` attr.
- **`Flicker.Messages`** — every visible string and every screen-reader
  announcement routes through this behaviour. Override globally via
  `config :flicker, messages:` or per-component via the `messages` attr.
- **`multiple`** — switches the value model to a list: selections render
  as removable chips, form-field mode emits `name[]` array inputs, and
  controlled mode's `on_select` carries the full selection list on every
  change. `max_selections` caps how many can be picked. Same component,
  no separate multi-select module.
- **`activate_with_keyboard`** — a chord string (e.g. `"mod+k"`) that
  focuses and opens this search from anywhere on the page — `mod`
  resolves to Cmd on macOS, Ctrl elsewhere. Bare-key chords (no modifier)
  raise `ArgumentError` at render time rather than silently hijacking
  ordinary typing.
- **`facets`** (on `Flicker.select/1`, and the whole point of
  `Flicker.search/1`) — Datadog-style `status:active worker:"Casey Nguyen"
  after:7d free text`. Pass bare facet keys/overrides (Tier 1, expanded by
  introspecting the resource's own type system) or a hand-built list of
  `Flicker.Facet` structs. An enum or boolean attribute gets a value
  picklist; a `belongs_to`/`has_*` facet opens a nested, actor-scoped
  record search over the related resource. A completed facet token also
  scopes *which records* `Flicker.select/1` offers — `status:active jo`
  only matches artists that are both active and match `jo`, not just the
  free-text portion — via `c:Flicker.Provider.search/2`, which every
  provider decides for itself how to honour (`Flicker.Providers.AshResource`
  filters by it; a custom provider is free to ignore `query.facets`, as
  `Flicker.Providers.Static` does). `Flicker.search/1` emits
  `{on_change, %Flicker.Query{}, filter}` — no selection semantics, you
  feed `filter` to your own table/stream/list.
- **`facet_trigger`** (on all three components, default `nil`) — a single
  character that opens the facet menu: `facet_trigger="@"`, or
  `%{"@" => [:worker], "#" => [:tag]}` to scope which facets each trigger
  offers. Without it every bare word offers facet keys, which is right for a
  dedicated filter bar and in the way for a search box that is mostly used
  for free text. **The trigger is input sugar, never grammar**: it reaches no
  token, pill, query or URL — `@stat` completes to `status:` — and a facet
  typed out in full or restored from a URL is still recognised, so shared
  search links keep working. Must not be a letter, digit, `_` or `?` (those
  can start a facet key); `@`, `#`, `/`, `:` are all fine, and a bad one
  raises at render time. Pairs with `open_editor_on_pick` (on
  `Flicker.search/1`, default `true`), which opens the picked facet's editor
  straight away instead of leaving you in value position.
- **`paginate`** (on `Flicker.select/1` and `Flicker.palette/1`, default
  `false`) — windowed infinite scroll instead of "keep typing to narrow":
  reaching the tail of the listbox loads and appends the next window.
  `max_windows` (default 10) caps how many windows load. Writing a custom
  provider? `search/2`'s `opts` gains an additive, optional `:offset`
  (default `0`) — implement it to support windowing, or ignore it safely
  (core detects the no-progress and stops asking after one extra probe).

## Basic usage

```heex
<Flicker.select
  id="client-select"
  field={@form[:client_id]}
  resource={MyApp.Client}
  actor={@current_user}
  search={[:first_name, :last_name, :uci_number]}
  option_label={:full_name}
/>
```

## Common patterns

### Controlled mode (no form)

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

### Multi-select with chips

```heex
<Flicker.select
  id="worker-select"
  field={@form[:worker_ids]}
  multiple
  resource={MyApp.Worker}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  max_selections={5}
/>
```

An edit form opening with `worker_ids` already set resolves every
preselected value in one `fetch/2` call, regardless of how many there are.

### Overriding a message

Only implement the keys you want to change; delegate the rest to
`Flicker.Messages.English`:

```elixir
defmodule MyAppWeb.FlickerMessages do
  @behaviour Flicker.Messages

  @impl true
  def message(:search_placeholder, _bindings), do: "Rechercher..."
  def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
end
```

```elixir
config :flicker, messages: MyAppWeb.FlickerMessages
```

### Overriding a theme part

```heex
<Flicker.select theme={%{search_input: "my-custom-input"}} ... />
```

A partial map/keyword override merges onto the base theme with
`struct!/2`; pass a full `%Flicker.Theme{}` (e.g. `Flicker.Theme.tailwind()`)
to replace it wholesale.

### Global keyboard shortcut

```heex
<Flicker.select
  id="site-search"
  source={MyApp.Search.Global}
  actor={@current_user}
  on_select={:result_selected}
  activate_with_keyboard="mod+k"
/>
```

Cmd+K (macOS) / Ctrl+K (elsewhere) focuses and opens this search from
anywhere on the page, even while another text input has focus. Pressing
it again while already focused and open toggles it closed.

### Faceted search filtering a list

```heex
<Flicker.search
  id="artist-search"
  resource={MyApp.Artist}
  actor={@current_user}
  facets={[:status, :genre, after: [attribute: :formed_on, op: :>=]]}
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

### Command palette (⌘K overlay)

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

```elixir
def handle_info(:palette_closed, socket), do: {:noreply, assign(socket, :palette_open, false)}
def handle_info({:palette_selected, _result}, socket), do: {:noreply, assign(socket, :palette_open, false)}
```

Wraps the same core as `Flicker.select/1` in a modal overlay: `mod+k`
opens/closes it self-contained; `open`/`on_close` additionally lets a
navbar button trigger it. A provider whose `Flicker.Result`s carry
`:group` gets contiguous group headers for free; a result whose
`meta.href` is set additionally navigates (`push_navigate/2`) on
selection — the raw `on_select` message still fires either way.

### Windowed search (infinite scroll)

```heex
<Flicker.select
  id="artist-select"
  field={@form[:artist_id]}
  resource={MyApp.Artist}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  paginate
  max_windows={20}
/>
```

For browsing-shaped populations, not typeahead-shaped ones — `paginate`
stays `false` by default because narrowing is the right default
interaction for most pickers.

### Driving a Cinder table (with shareable URLs)

```heex
<Flicker.search
  id="artist-search"
  resource={MyApp.Artist}
  actor={@current_user}
  facets={[:status, :genre]}
  text={@search_text}
  on_change={:artist_query_changed}
/>

<Cinder.collection query={@filtered_query} actor={@current_user} show_filters={false} url_state={@url_state}>
  ...
</Cinder.collection>
```

```elixir
alias Flicker.Integrations.Cinder, as: FlickerCinder

def handle_params(params, uri, socket) do
  facets = FlickerCinder.facets(%{resource: MyApp.Artist, facets: [:status, :genre]})
  {text, _query, filter} = FlickerCinder.restore(params, facets)

  socket =
    params
    |> Cinder.UrlSync.handle_params(uri, socket)
    |> assign(:search_text, text)
    |> assign(:filtered_query, FlickerCinder.query(MyApp.Artist, filter))

  {:noreply, socket}
end

def handle_info({:artist_query_changed, query, filter}, socket) do
  socket =
    socket
    |> assign(:filtered_query, FlickerCinder.query(MyApp.Artist, filter))
    |> FlickerCinder.push_patch(~p"/artists", query)

  {:noreply, socket}
end
```

`Flicker.Integrations.Cinder` compiles only when `cinder` is in your own
deps. It serialises the raw typed string under a namespaced `flicker_q`
param, coexisting with Cinder's own `UrlSync` params (`page`, `sort`,
...) — a shared URL restores both. One rule: a field is filtered by a
Flicker facet *or* a Cinder column filter, never both
(`show_filters={false}` when Flicker owns filtering;
`FlickerCinder.overlapping_fields/2` guards the convention in a test).

### Testing a select

```elixir
test "picks a client", %{conn: conn} do
  conn
  |> visit(~p"/clients/new")
  |> Flicker.Test.search_select("Search...", "Casey Cassidy")
  |> assert_has("#client-select-input[value='Casey Cassidy']")
end
```

Requires `phoenix_test` in your own `:test` deps.

## Anti-patterns

- Do **not** omit `actor` — there's no other read-authorization boundary;
  every result and every `fetch` resolves with whatever that actor can
  see.
- Do **not** write a partial `Flicker.Messages` override that raises
  inside a clause it does handle — `Flicker.Messages.get/3` only falls
  back to `Flicker.Messages.English` when the override doesn't implement
  a key at all (a `FunctionClauseError`), not when an implemented clause
  itself errors.
- Avoid reaching for a custom `Flicker.Provider` when Tier 1 config
  (`resource` + `search` + `option_label`) already covers the case — it's
  strictly less code and stays authorized the same way.

## See also

- [HexDocs](https://hexdocs.pm/flicker)
- [Getting started guide](https://hexdocs.pm/flicker/getting-started.html)
