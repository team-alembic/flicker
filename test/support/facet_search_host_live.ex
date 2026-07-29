if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.FacetSearchHostLive do
    @moduledoc """
    A host `LiveView` exercising `Flicker.search/1` end-to-end against
    `Flicker.Test.FacetArtist`/`Flicker.Test.FacetGenre` (Spec 003) — no
    selection semantics, just the emitted `%Flicker.Query{}`/filter.

    Test-support only; only compiled when `ash` is present.
    """

    use Phoenix.LiveView

    alias Flicker.Test.FacetDomain

    @impl true
    def mount(_params, session, socket) do
      actor = Map.get(session, "actor", %{label: nil})
      dispatch = Map.get(session, "dispatch", :debounce)

      FacetDomain.seed!()

      socket =
        socket
        |> assign(:actor, actor)
        |> assign(:dispatch, dispatch)
        |> assign(:last_query, nil)
        |> assign(:last_filter, nil)

      {:ok, socket}
    end

    @impl true
    def handle_info({:artist_query_changed, query, filter}, socket) do
      {:noreply, socket |> assign(:last_query, query) |> assign(:last_filter, filter)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <Flicker.search
        id="artist-search"
        resource={Flicker.Test.FacetArtist}
        actor={@actor}
        facets={[{:status, value_colors: %{active: "#16a34a"}}, :genre, :verified?]}
        on_change={:artist_query_changed}
        dispatch={@dispatch}
      />
      <p :if={@last_query} id="last-text">{@last_query.text}</p>
      <p :if={@last_query} id="last-facets">{inspect(@last_query.facets)}</p>
      <p :if={@last_filter} id="last-filter">{inspect(@last_filter)}</p>
      """
    end
  end
end
