# Command palette

`Flicker.palette/1` is a ⌘K fullscreen command-palette overlay: backdrop,
centred panel, large search input, grouped result list, and a footer of
keyboard hints (↑↓ navigate · ↵ select · esc close). It wraps the exact
same core `Flicker.select/1` runs on — same provider tiers, same
`Flicker.Result`/`Flicker.Provider` contract — as a modal overlay instead
of an inline combobox. There's no special machinery behind it: it's
`activate_with_keyboard` + a federated provider + theme parts arranged
into one component.

## Basic usage

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

`on_close` and `on_select` are both required — there's no form-field mode
for a modal overlay, only controlled mode. The host receives a bare
`on_close` message (`send(self(), on_close)`, no payload) whenever the
overlay closes, and `{on_select, %Flicker.Result{}}` on selection.

## Opening it

Two independent ways to open the palette, usable together:

- **`activate_with_keyboard`** (defaults to `"mod+k"`) — self-contained,
  needs no host state. The chord opens/closes the overlay entirely from
  the client side, the same activation pattern `Flicker.select/1` uses.
- **The `open`/`on_close` controlled pair** — for a navbar button or any
  other host-driven trigger. `open` is adopted whenever it *changes*
  between renders: a rising edge opens the overlay, a falling edge closes
  it. In between, the component is free to open or close itself (the
  chord, `Escape`, a backdrop click) and always fires `on_close` so host
  state never drifts out of sync with what's actually on screen.

```heex
<button phx-click="open_palette">Search</button>

<Flicker.palette
  id="cmdk"
  source={MyApp.Search.Global}
  actor={@current_user}
  open={@palette_open}
  on_close={:palette_closed}
  on_select={:palette_selected}
  activate_with_keyboard="mod+k"
/>
```

```elixir
def handle_event("open_palette", _params, socket), do: {:noreply, assign(socket, :palette_open, true)}
```

## Federated search with groups

The palette's value comes from a `source` that searches more than one
resource in a single call, tagging each `Flicker.Result` with `:group` so
the result list renders contiguous group headers. Grouping is entirely
the provider's own choice — the palette never re-sorts by group, it just
draws a header before the first result of each new group as encountered:

```elixir
defmodule MyApp.Search.Global do
  @behaviour Flicker.Provider

  alias Flicker.{Query, Result}

  @impl true
  def search(%Query{text: text}, opts) do
    actor = Keyword.get(opts, :actor)

    artists = MyApp.Artist |> search_by(:name, text) |> Ash.read!(actor: actor)
    albums = MyApp.Album |> search_by(:title, text) |> Ash.read!(actor: actor)

    results =
      Enum.map(artists, &to_result(&1, "Artists", &1.name)) ++
        Enum.map(albums, &to_result(&1, "Albums", &1.title))

    {:ok, results}
  end

  @impl true
  def fetch(_values, _opts), do: {:ok, []}

  defp to_result(record, group, label) do
    %Result{
      value: record.id,
      label: label,
      group: group,
      meta: %{href: ~p"/#{group |> String.downcase()}/#{record.id}"}
    }
  end
end
```

## Navigate on select

A result whose `meta.href` is set additionally navigates
(`push_navigate/2`) when it's chosen — the raw `on_select` message still
fires either way, so a host doing something other than navigating
(closing the palette, logging, a custom side effect) always can. Omit
`meta.href` for a result that should only fire `on_select` — e.g. running
an in-page action instead of going anywhere.

## Theming

`Flicker.palette/1` uses the same `Flicker.Theme` as `Flicker.select/1`,
plus five overlay-specific parts: `:backdrop`, `:panel`, `:palette_input`
(in place of `:search_input`), `:group_header`, and `:footer`. See the
[theming guide](theming.md) for the full part list and preset system.

## See also

- `Flicker.palette/1` — the full moduledoc.
- [Providers](providers.md) — writing a federated `Flicker.Provider` like
  the one above.
- [Faceted search](faceted-search.md) — the same `facets` attr narrows a
  palette's free-text search too.
