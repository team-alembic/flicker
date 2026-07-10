if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.FacetSelectHostLive do
    @moduledoc """
    A host `LiveView` exercising the `facets` attr on `Flicker.select/1`
    end-to-end against `Flicker.Test.FacetArtist` (Spec 003) — key/value
    facet suggestions inside the same listbox a record search would use.

    Test-support only; only compiled when `ash` is present.
    """

    use Phoenix.LiveView

    alias Flicker.Test.FacetDomain

    @impl true
    def mount(_params, session, socket) do
      actor = Map.get(session, "actor", %{label: nil})

      FacetDomain.seed!()

      socket =
        socket
        |> assign(:actor, actor)
        |> assign(:selected_result, :none)

      {:ok, socket}
    end

    @impl true
    def handle_info({:artist_selected, result}, socket) do
      {:noreply, assign(socket, :selected_result, result)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <Flicker.select
        id="artist-picker"
        resource={Flicker.Test.FacetArtist}
        actor={@actor}
        search={[:name]}
        option_label={:name}
        facets={[:status, :genre, :verified?]}
        on_select={:artist_selected}
      />
      <p :if={@selected_result != :none} id="selection">
        {if @selected_result, do: @selected_result.label, else: "cleared"}
      </p>
      """
    end
  end
end
