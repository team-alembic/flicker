defmodule Dev.Live.CinderInterop do
  @moduledoc """
  Playground page for [Spec 009 Level 1](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
  — the no-code-required recipe for pairing `Flicker.search/1` with a
  `Cinder.collection` over the same resource.

  `Flicker.search` never lists records itself; every keystroke it emits
  `{on_change, query, filter}` to the host (Spec 003). This page composes
  that `filter` onto a base `Ash.Query` for `Dev.Music.Artist` with
  `Ash.Query.filter_input/2` and hands the result to `Cinder.collection`'s
  `query` attr — Cinder narrows its own table live, with no Cinder-specific
  code inside Flicker. `show_filters={false}` because Flicker owns
  filtering here (Spec 009's double-filter guidance): the two libraries
  never fight over the same field.

  An actor toggle proves the recipe is actor-scoped end to end: both the
  search's own suggestions and the query it composes run under
  `@actor`, and Cinder reads the resulting query under the same actor —
  so a labelled artist that actor can't see never reaches the table.
  """

  use Phoenix.LiveView

  alias Dev.Music.Artist

  @actors [
    {"Public (no label)", nil},
    {"Indie label", "indie"},
    {"Major label", "major"}
  ]

  @impl true
  @doc "Seeds `Dev.Music` and builds the unfiltered base query."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
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
  @doc "Switches the acting actor's `:label`, changing which artists Cinder can read."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_actor", %{"label" => label}, socket) do
    {:noreply, assign(socket, :actor_label, normalize_label(label))}
  end

  defp normalize_label(""), do: nil
  defp normalize_label(label), do: label

  @impl true
  @doc """
  Composes `Flicker.search/1`'s emitted filter onto the base query on
  every keystroke — an empty/`nil` filter (the search cleared) restores
  the unfiltered query.
  """
  @spec handle_info({atom(), Flicker.Query.t(), map() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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
  @doc "Renders the actor toggle, the search bar, and the Cinder collection it drives."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
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
