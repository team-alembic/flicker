# Getting started

Flicker is a type-to-search, pick-one combobox for Phoenix LiveView that
reads directly off an Ash resource — no options plumbing, no host web
module, no `~p`. This guide takes you from a fresh dependency to a working
select in a form.

## Install

The fastest path is [Igniter](https://hex.pm/packages/igniter):

```bash
mix igniter.install flicker
```

This adds `flicker` to `mix.exs`, imports it into your `.formatter.exs`,
adds `config :flicker, default_limit: 25, default_debounce: 150` to
`config/config.exs`, and wires the keyboard-nav colocated hook into your
`assets/js/app.js` — no manual JS wiring needed.

Installing by hand instead? Add the dependency:

```elixir
def deps do
  [{:flicker, "~> 0.1"}]
end
```

then wire the colocated hook into `assets/js/app.js` yourself — it ships
as a `Phoenix.LiveView.ColocatedHook` (requires Phoenix 1.8+), aggregated
per-dependency under its own manifest:

```javascript
import {hooks as flickerHooks} from "phoenix-colocated/flicker"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...flickerHooks},
  // merge in your own colocated hooks too, if you have any:
  // hooks: {...colocatedHooks, ...flickerHooks},
  ...
})
```

## Your first select

The common case — a resource and a few field names, no provider module of
your own — is **Tier 1 declarative config**:

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

- `resource` — the Ash resource to read.
- `actor` — passed straight through to Ash's authorizer and policies; a
  record the actor can't read never appears in results.
- `search` — the attributes the typed text matches against.
- `option_label` — an atom (a struct field) or a 1-arity function
  producing the row's display label.
- `option_sublabel` — same shape, for the smaller secondary line.
- `read_action`, `sort`, `filter` — optional; narrow or order what's
  searched.

Reaching for federated search across multiple sources, or a data source
that isn't an Ash resource at all? Pass `source` (a module or
`{module, opts}` implementing `Flicker.Provider`) instead of `resource` —
see `Flicker.Provider`'s moduledoc.

## Form mode vs. controlled mode

`Flicker.select/1` runs in exactly one of two modes, chosen by which attr
you pass:

**Form-field mode** — pass `field` (a `Phoenix.HTML.FormField`, e.g.
`@form[:client_id]`), as in the example above. The component owns its own
hidden input and submits the selected value under that field's name.
Required-field errors don't fire until the field is engaged, and the
selection survives a LiveSocket reconnect. If your form is backed by
`AshPhoenix.Form`, attach the adapter once in `mount/3` so a selection
merges into the form without wiping other fields' in-progress state:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(form: to_form(AshPhoenix.Form.for_create(MyApp.Client, :create)))
   |> Flicker.AshPhoenixForm.attach(form: :form)}
end
```

**Controlled mode** — omit `field` and pass `on_select` (an atom) instead.
No form inputs are rendered; your `handle_info/2` receives
`{on_select, %Flicker.Result{} | nil}` (`nil` on clear):

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

## Testing a select

`Flicker.Test.search_select/3` drives a picker the way a user would —
open it, type to filter, pick a result — from a `PhoenixTest` session:

```elixir
test "picks a client", %{conn: conn} do
  conn
  |> visit(~p"/clients/new")
  |> Flicker.Test.search_select("Search...", "Casey Cassidy")
  |> assert_has("#client-select-input[value='Casey Cassidy']")
end
```

Requires `phoenix_test` in your own `:test` deps (most PhoenixTest users
already have it).

## Windowed search (infinite scroll)

The shipped default — "keep typing to narrow" — treats narrowing as the
interaction: type more, see less, until you're at the record you want.
That's the right model for most typeahead pickers. For a browsing-shaped
population (a few hundred mostly-unfamiliar options the user wants to
*scan*, not narrow), pass `paginate`:

```heex
<Flicker.select
  id="artist-select"
  field={@form[:artist_id]}
  resource={MyApp.Artist}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  paginate
/>
```

Scrolling to the tail of the listbox (or pressing `ArrowDown` on the last
option) loads the next `limit`-sized window and appends it — no page
numbers, no "next" button, just more results. `max_windows` (default 10)
caps how many windows load before the tail falls back to the same "keep
typing" hint the non-`paginate`d default shows; a new query always resets
back to the first window. `paginate` is `false` by default on both
`Flicker.select/1` and `Flicker.palette/1` — turning it on is a per-picker
UX decision, not a new global default (see
[Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md)
for the full design).

Writing your own `Flicker.Provider`? `search/2`'s `opts` gains an
additive, optional `:offset` (default `0`) — implement it and windowing
works; ignore it and your provider keeps working exactly as it does today
(core detects a provider that ignores `:offset` and stops asking after one
extra probe, never looping forever).

## Theming

Every visually distinct part of the rendered markup — the wrapper, the
input, the listbox, an option, its active state, and more — has a named
key in `Flicker.Theme`. Three presets ship: `Flicker.Theme.vanilla/0`
(plain, framework-free class names — the default),
`Flicker.Theme.tailwind/0`, and `Flicker.Theme.daisy_ui/0`. Set one
globally:

```elixir
config :flicker, default_theme: Flicker.Theme.tailwind()
```

or per-component, with a full preset or a partial override of just the
parts you want to change:

```heex
<Flicker.select theme={%{search_input: "my-custom-input"}} ... />
```

See `Flicker.Theme`'s moduledoc for the full list of parts, and
`Flicker.Messages` for overriding the (English-default) strings the
component renders and announces.
