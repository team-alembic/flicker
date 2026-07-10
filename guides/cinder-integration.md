# Cinder interop

[Cinder](https://hexdocs.pm/cinder) is a data-table component for Phoenix
LiveView with the same Ash-native pedigree as Flicker: read directly off
an Ash resource, authorise via `actor:`, no options plumbing. Cinder
answers "how do I render this collection?"; Flicker answers "which
records am I looking at?" — `Flicker.search/1` above a `Cinder.collection`
is the pairing both libraries were built for.

This guide covers **Level 1** from
[Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md):
the recipe, no code required in either library. `Flicker.search/1` has no
selection semantics — it never lists records itself. Every keystroke it
parses the typed text and sends the host `{on_change, %Flicker.Query{},
filter}`, where `filter` is a map suitable for `Ash.Query.filter_input/2`.
The host composes that filter onto a base `Ash.Query` and hands the
result to `Cinder.collection`'s `query` attribute — Cinder accepts a
pre-built query alongside (instead of) a bare `resource`, so this is
pure query composition, no adapter, no glue code.

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

## The recipe

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

`show_filters={false}` matters: Flicker owns filtering here, so Cinder's
own column filters are switched off rather than fighting over the same
fields. If a column needs filtering that `Flicker.search`'s facets don't
cover, that's the one field Cinder's own filter UI should own instead —
pick one owner per field, never both.

Both components read `actor={@actor}` — the search's own suggestions
(e.g. a relationship facet's nested search) and the query it composes
run under that actor, and Cinder reads the resulting query under the
same actor, so the whole path is actor-scoped end to end. A record the
actor can't read never reaches the table, whether it was excluded by the
facet filter or by policy.

## The playground page, verbatim

The dev playground's `/cinder-interop` page (`Dev.Live.CinderInterop`) is
exactly this recipe against the seeded `Dev.Music.Artist` domain, plus an
actor toggle so the policy-bearing resource's visibility is visible:

```elixir
defmodule Dev.Live.CinderInterop do
  use Phoenix.LiveView

  alias Dev.Music.Artist

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
      |> assign(:filtered_query, base_query(%{}))

    {:ok, socket}
  end

  @impl true
  def handle_event("set_actor", %{"label" => label}, socket) do
    {:noreply, assign(socket, :actor_label, normalize_label(label))}
  end

  defp normalize_label(""), do: nil
  defp normalize_label(label), do: label

  @impl true
  def handle_info({:artist_query_changed, _query, filter}, socket) do
    {:noreply, assign(socket, :filtered_query, base_query(filter))}
  end

  defp base_query(nil), do: base_query(%{})

  defp base_query(filter) do
    Artist
    |> Ash.Query.filter_input(filter)
    |> Ash.Query.sort(:name)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :actor, %{label: assigns.actor_label})

    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold">Cinder interop</h1>
      <p class="text-sm text-gray-600">
        Try <code>status:active</code>, <code>tier:legendary</code>, or free
        text — <code>Flicker.search</code> narrows the <code>Cinder.collection</code>
        below it live via query composition, no Cinder-specific code in
        Flicker itself. Clearing the search restores the full table.
      </p>

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
    </div>
    """
  end
end
```

Run `mix dev` and visit `/cinder-interop` to try it live: type
`status:active`, switch the actor toggle, watch the table narrow and the
label-gated rows appear or disappear together. `test/flicker/cinder_interop_test.exs`
drives this exact LiveView, so the recipe can't quietly rot.

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

This guide covers Level 1 only. A blessed `Flicker.Integrations.Cinder`
adapter (Level 2) — namespaced URL-state coordination with Cinder's own
`UrlSync`, plus guidance for facets and Cinder column filters
coexisting — and any upstream Cinder-side integration (Level 3) are
tracked, not yet built; see Spec 009 for the plan.
