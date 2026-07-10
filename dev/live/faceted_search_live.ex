defmodule Dev.Live.FacetedSearch do
  @moduledoc """
  `Flicker.search/1` filtering a live list of `Dev.Music.Artist` (Spec 003,
  Spec 005's playground) — the standalone faceted filter bar, no selection
  semantics: every keystroke's `on_change` re-reads the artist list with the
  emitted Ash filter.

  Deliberately doesn't configure the `:genre` relationship facet here: the
  seeded `Dev.Music` resources run on `private?: true` ETS (isolated per
  calling process — see `Dev.Music`'s moduledoc), and a relationship
  facet's nested search runs in its own `start_async` task, a different
  process from the one that seeded this page's data. `:status`, `:tier`,
  `:monthly_listeners`, and `:formed_on` (via the `after:` alias) cover the
  enum/numeric/date rows of the type table without that mismatch; a
  relationship-facet example lives in the test suite instead, against a
  shared (non-private) fixture resource built for it.
  """

  use Phoenix.LiveView

  alias Dev.Music

  @impl true
  @doc "Seeds `Dev.Music` and loads the unfiltered artist list."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Music.seed!()

    socket =
      socket
      |> assign(:actor, %{label: nil})
      |> assign(:artists, list_artists(nil))

    {:ok, socket}
  end

  @impl true
  @doc "Re-reads the artist list through the emitted Ash filter on every `Flicker.search/1` keystroke."
  @spec handle_info({atom(), Flicker.Query.t(), map() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:artist_query_changed, _query, filter}, socket) do
    {:noreply, assign(socket, :artists, list_artists(filter))}
  end

  defp list_artists(nil), do: list_artists(%{})

  defp list_artists(filter) do
    Dev.Music.Artist
    |> Ash.Query.filter_input(filter)
    |> Ash.Query.sort(:name)
    |> Ash.read!(actor: %{label: nil})
  end

  @impl true
  @doc "Renders the facet search bar and the live-filtered artist list beneath it."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold">Faceted search</h1>
      <p class="text-sm text-gray-600">
        Try <code>status:active</code>, <code>tier:legendary</code>,
        <code>after:1980-01-01</code>, or free text — the list below is a
        plain <code>Ash.read!/2</code> against the emitted filter, not part
        of the component.
      </p>
      <Flicker.search
        id="artist-search"
        resource={Dev.Music.Artist}
        actor={@actor}
        facets={[:status, :tier, :monthly_listeners, after: [attribute: :formed_on, op: :>=]]}
        on_change={:artist_query_changed}
      />
      <ul class="divide-y divide-gray-200">
        <li :for={artist <- @artists} class="py-2">
          <span class="font-medium">{artist.name}</span>
          <span class="text-sm text-gray-500">— {artist.status} · {artist.tier}</span>
        </li>
        <li :if={@artists == []} class="py-2 text-sm text-gray-500">No artists match.</li>
      </ul>
    </div>
    """
  end
end
