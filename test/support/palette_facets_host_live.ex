if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.PaletteFacetsHostLive do
    @moduledoc """
    A host `LiveView` exercising `facets` on `Flicker.palette/1` end-to-end
    (Spec 008's now-closed open question: `Flicker.palette/1` accepted and
    forwarded `facets`, but it hadn't been exercised end-to-end) — against
    `Flicker.Test.FacetArtist`, the same Tier 1 fixture
    `Flicker.Test.FacetSelectHostLive` drives for `Flicker.select/1`'s
    `facets` attr, reused here to prove the palette's thin wrapper forwards
    it to the nested core exactly the same way.

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
        |> assign(:palette_open, Map.get(session, "open", true))
        |> assign(:selected_result, :none)

      {:ok, socket}
    end

    @impl true
    def handle_info(:palette_closed, socket), do: {:noreply, assign(socket, :palette_open, false)}

    def handle_info({:palette_selected, result}, socket) do
      socket = socket |> assign(:selected_result, result) |> assign(:palette_open, false)
      {:noreply, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <p :if={@selected_result != :none} id="palette-selection">
        {if @selected_result, do: @selected_result.label, else: "cleared"}
      </p>
      <Flicker.palette
        id="cmdk"
        resource={Flicker.Test.FacetArtist}
        actor={@actor}
        search={[:name]}
        option_label={:name}
        facets={[:status, :genre, :verified?]}
        open={@palette_open}
        on_close={:palette_closed}
        on_select={:palette_selected}
      />
      """
    end
  end
end
