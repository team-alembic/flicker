# Cinder interop

[Cinder](https://hexdocs.pm/cinder) is a data-table component for Phoenix
LiveView with the same Ash-native pedigree as Flicker: read directly off
an Ash resource, authorise via `actor:`, no options plumbing. Cinder
answers "how do I render this collection?"; Flicker answers "which
records am I looking at?" — `Flicker.search/1` above a `Cinder.collection`
is the pairing both libraries were built for.

This guide covers both interop levels from
[Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md):
**Level 1**, the no-adapter recipe (pure query composition, no code
required in either library), and **Level 2**, the blessed
`Flicker.Integrations.Cinder` adapter (less boilerplate, plus URL state
coordinated with Cinder's own `Cinder.UrlSync` so back/forward/share
reproduces both libraries' state).

## Add the dependency

Cinder isn't a Flicker dependency — add it to your own app:

```elixir
def deps do
  [
    {:flicker, "~> 0.1"},
    {:cinder, "~> 0.15"}
  ]
end
```

`Flicker.Integrations.Cinder` compiles automatically once `cinder` is in
your deps (the same `Code.ensure_loaded?/1` boundary Flicker's `ash`
integration uses) — nothing to configure, and nothing extra in a build
without it.

## Level 1: the recipe, no adapter

`Flicker.search/1` has no selection semantics — it never lists records
itself. Every keystroke it parses the typed text and sends the host
`{on_change, %Flicker.Query{}, filter}`, where `filter` is a map suitable
for `Ash.Query.filter_input/2`. The host composes that filter onto a base
`Ash.Query` and hands the result to `Cinder.collection`'s `query`
attribute — Cinder accepts a pre-built query alongside (instead of) a
bare `resource`, so this is pure query composition, no adapter, no glue
code:

```heex
<Flicker.search
  id="artist-search"
  resource={Artist}
  actor={@actor}
  facets={[:status, :tier, :monthly_listeners]}
  on_change={:artist_query_changed}
/>

<Cinder.collection
  id="artist-collection"
  query={@filtered_query}
  actor={@actor}
  show_filters={false}
>
  <:col :let={artist} field="name" sort>{artist.name}</:col>
  <:col :let={artist} field="status">{artist.status}</:col>
  <:col :let={artist} field="tier">{artist.tier}</:col>
  <:col :let={artist} field="monthly_listeners" sort>{artist.monthly_listeners}</:col>
</Cinder.collection>
```

```elixir
def handle_info({:artist_query_changed, _query, filter}, socket) do
  {:noreply, assign(socket, :filtered_query, base_query(filter))}
end

defp base_query(nil), do: base_query(%{})

defp base_query(filter) do
  Artist
  |> Ash.Query.filter_input(filter)
  |> Ash.Query.sort(:name)
end
```

Every keystroke re-runs `base_query/1` with the newly emitted filter and
reassigns `@filtered_query`; Cinder re-reads under the new query and
narrows the table. Clearing the search emits an empty filter (`%{}`),
which `Ash.Query.filter_input/2` turns into "no filter" — the unfiltered
query, and the full table, come back.

Both components read `actor={@actor}` — the search's own suggestions
(e.g. a relationship facet's nested search) and the query it composes
run under that actor, and Cinder reads the resulting query under the
same actor, so the whole path is actor-scoped end to end. A record the
actor can't read never reaches the table, whether it was excluded by the
facet filter or by policy.

## One field, one filter owner

`show_filters={false}` above matters: Flicker owns filtering there, so
Cinder's own column filters are switched off rather than fighting over
the same fields. The convention (either level): **a field is filtered in
one place, not both.** If a column needs filtering that `Flicker.search`'s
facets don't cover, that's the one field Cinder's own filter UI should
own instead — never configure a Flicker facet and a Cinder `<:col
filter>` over the same field at once. The two would apply independently
(an unsatisfiable AND neither component can see), confusing anyone who
cleared one filter and still sees narrowed results. Sorting doesn't
count: `<:col sort>` on a faceted field is fine — ordering isn't
filtering.

`Flicker.Integrations.Cinder.overlapping_fields/2` guards the convention
mechanically: give it your facet keys and the fields your columns declare
`filter` on, and assert the result stays empty in a test — a facet and a
column filter can then never quietly drift onto the same field as either
configuration changes.

## Level 2: the adapter, with URL state

Level 1 leaves two things on the table: the `base_query/1` boilerplate,
and the URL. Both libraries want query params — Cinder's `Cinder.UrlSync`
manages `page`, `sort`, `page_size`, `search`, `after`, `before`, and one
param per filterable column — so Flicker's search must live in a param of
its own that can't collide. `Flicker.Integrations.Cinder` reserves
**`flicker_q`** and gives you the pieces:

  * `query/2` — composes the emitted `filter` onto a base
    resource/query: the whole of `base_query/1`, one call.
  * `push_patch/4` — patches the URL with the raw typed string under
    `flicker_q`, preserving every other param (Cinder's included).
  * `restore/2` — the `handle_params/3` side: reads `flicker_q` back,
    re-parses it, and returns `{text, query, filter}`.
  * `facets/1` — resolves the same facet registry `Flicker.search/1`
    uses internally, so `restore/2` parses against identical facets.

The param carries the *raw input string*, exactly as typed — never a
reconstruction from the parsed struct, which is lossy (`active?:TRUE`
parses to `true`; `after:7d` resolves to a date; quoting disappears).
Restoring re-parses the original string, so a shared URL reproduces the
exact query, and `Flicker.search/1`'s `text` attr (adopted once, on
mount) pre-fills the input with it.

## The playground page, verbatim

The dev playground's `/cinder-interop` page (`Dev.Live.CinderInterop`) is
exactly this adapter recipe against the seeded `Dev.Music.Artist` domain,
plus an actor toggle so the policy-bearing resource's visibility is
visible (moduledoc, `@doc`s, and the drift-test accessors elided here —
see the file for the full version):

```elixir
defmodule Dev.Live.CinderInterop do
  use Phoenix.LiveView
  use Cinder.UrlSync

  alias Dev.Music.Artist
  alias Flicker.Integrations.Cinder, as: FlickerCinder

  @path "/cinder-interop"
  @facet_keys [:status, :tier, :monthly_listeners]

  @actors [
    {"Public (no label)", nil},
    {"Indie label", "indie"},
    {"Major label", "major"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:actors, @actors)
      |> assign(:actor_label, nil)
      |> assign(:facets, FlickerCinder.facets(%{resource: Artist, facets: @facet_keys}))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {text, _query, filter} = FlickerCinder.restore(params, socket.assigns.facets)

    socket =
      params
      |> Cinder.UrlSync.handle_params(uri, socket)
      |> assign(:search_text, text)
      |> assign(:filtered_query, FlickerCinder.query(base_query(), filter))

    {:noreply, socket}
  end

  defp base_query, do: Ash.Query.sort(Artist, :name)

  @impl true
  def handle_event("set_actor", %{"label" => label}, socket) do
    {:noreply, assign(socket, :actor_label, normalize_label(label))}
  end

  defp normalize_label(""), do: nil
  defp normalize_label(label), do: label

  @impl true
  def handle_info({:artist_query_changed, query, filter}, socket) do
    socket =
      socket
      |> assign(:filtered_query, FlickerCinder.query(base_query(), filter))
      |> FlickerCinder.push_patch(@path, query, current_params(socket))

    {:noreply, socket}
  end

  defp current_params(socket) do
    case get_in(socket.assigns, [:url_state, :uri]) do
      nil -> %{}
      uri -> uri |> URI.parse() |> Map.get(:query) |> Kernel.||("") |> URI.decode_query()
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :actor, %{label: assigns.actor_label})

    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold">Cinder interop (Level 2)</h1>

      <fieldset class="flex flex-wrap items-center gap-2">
        <legend class="mb-1 text-sm font-medium">Acting as</legend>
        <button
          :for={{name, label} <- @actors}
          type="button"
          phx-click="set_actor"
          phx-value-label={label || ""}
          class={[
            "rounded px-3 py-1 text-sm",
            if(@actor_label == label, do: "bg-indigo-600 text-white", else: "bg-gray-200")
          ]}
        >
          {name}
        </button>
      </fieldset>

      <Flicker.search
        id="artist-search"
        resource={Artist}
        actor={@actor}
        facets={@facets}
        text={@search_text}
        on_change={:artist_query_changed}
      />

      <Cinder.collection
        id="artist-collection"
        query={@filtered_query}
        actor={@actor}
        show_filters={false}
        url_state={@url_state}
      >
        <:col :let={artist} field="name" sort>{artist.name}</:col>
        <:col :let={artist} field="status">{artist.status}</:col>
        <:col :let={artist} field="tier">{artist.tier}</:col>
        <:col :let={artist} field="monthly_listeners" sort>{artist.monthly_listeners}</:col>
      </Cinder.collection>
    </div>
    """
  end
end
```

Worth noting in there:

  * **`use Cinder.UrlSync` + `url_state={@url_state}`** wire up Cinder's
    own URL sync (sort a column and watch `?sort=` appear); the adapter's
    `push_patch/4` and `restore/2` slot Flicker's `flicker_q` in beside
    it. Neither clobbers the other: Cinder's `build_url` treats
    `flicker_q` as a custom param and preserves it, and `put_params/2`
    (inside `push_patch/4`) touches only its own key.
  * **`current_params/1`** re-reads the *current URL's* params (Cinder
    patches the URL directly on a sort click, without this page seeing
    it), so a Flicker patch always merges into the browser's actual
    state, never a stale copy.
  * **`text={@search_text}`** pre-fills the input from a restored URL.
    It's adopted once, on the component's first mount — the component
    owns the text thereafter, so the assign changing later (every
    `handle_params`) doesn't fight the user's typing.
  * **The base query keeps an explicit sort** — which rows land on
    Cinder's first page shouldn't depend on data-layer ordering.

Run `mix dev` and visit `/cinder-interop` to try it live: type
`status:active`, sort a column, copy the address bar into a new tab —
the same narrowed, sorted table comes back, and the search input arrives
pre-filled. `test/flicker/cinder_interop_test.exs` drives this exact
LiveView (including the URL round-trip and param coexistence), and
`test/flicker/integrations/cinder_test.exs` covers the adapter's own
contract, so neither level's recipe can quietly rot.

## A caveat for `Ash.DataLayer.Ets`

Cinder's own data load runs in a `start_async` task — a different process
from whichever one seeded the data. `Ash.DataLayer.Ets`'s `private?: true`
tables (like the ones `Dev.Music.seed!/0` creates) are scoped to the
calling *process*, so a Cinder table over a private ETS resource reads an
empty table it can't see into. The playground and its test both run with
`config :ash, disable_async?: true` (Cinder honours this to load
synchronously in the same process) to work around it — a real app backed
by Postgres or a non-private ETS table never hits this.

## What's next

Levels 1 and 2 are both shipped. Any upstream Cinder-side integration
(Level 3 — Flicker as Cinder's own configured search control) is tracked,
not promised; see Spec 009 for the plan.
