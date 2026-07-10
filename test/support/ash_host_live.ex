if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Test.AshHostLive do
    @moduledoc """
    A host `LiveView` exercising `Flicker.select/1`'s Tier 1 (declarative
    resource) config against `Flicker.Test.PolicyArtist` — proving actor
    scoping holds through the full component (search runs in a
    `start_async` task), not just the provider.

    Test-support only; only compiled when `ash` is present.
    """

    use Phoenix.LiveView

    alias Flicker.Test.PolicyDomain

    @impl true
    def mount(_params, session, socket) do
      actor = Map.get(session, "actor", %{label: nil})

      PolicyDomain.seed!()

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
        resource={Flicker.Test.PolicyArtist}
        actor={@actor}
        search={[:name]}
        option_label={:name}
        on_select={:artist_selected}
      />
      <p :if={@selected_result != :none} id="selection">
        {if @selected_result, do: @selected_result.label, else: "cleared"}
      </p>
      """
    end
  end
end
