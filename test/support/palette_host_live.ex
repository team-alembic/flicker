defmodule Flicker.Test.PaletteHostLive do
  @moduledoc """
  A minimal host `LiveView` for driving `Flicker.palette/1` with
  PhoenixTest (Spec 008).

  Backed by `Flicker.Providers.Static` with a small grouped result set —
  no Ash data layer at all, proving the palette stands alone on a pure
  provider (ADR-006). The `"grouped"` session key (default `true`) toggles
  whether the fixture results carry `:group`, so the same fixture also
  covers "a groupless provider renders identically to today".
  """

  use Phoenix.LiveView

  @grouped_results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", group: "Artists"},
    %Flicker.Result{value: "2", label: "Casey's Album", group: "Albums"},
    %Flicker.Result{value: "3", label: "Casey's Other Album", group: "Albums"},
    %Flicker.Result{
      value: "4",
      label: "Cassidy Records",
      group: "Labels",
      meta: %{href: "/records/label/4"}
    }
  ]

  @groupless_results [
    %Flicker.Result{value: "1", label: "Casey Cassidy"},
    %Flicker.Result{value: "2", label: "Casey's Album"},
    %Flicker.Result{value: "3", label: "Casey's Other Album"},
    %Flicker.Result{value: "4", label: "Cassidy Records"}
  ]

  @impl true
  def mount(_params, session, socket) do
    grouped = Map.get(session, "grouped", true)
    results = if grouped, do: @grouped_results, else: @groupless_results
    silent = Map.get(session, "silent", false)

    socket =
      socket
      |> assign(:results, results)
      |> assign(:palette_open, Map.get(session, "open", false))
      |> assign(:close_count, 0)
      |> assign(:selected_result, :none)
      |> assign(:silent, silent)

    {:ok, socket}
  end

  @impl true
  def handle_event("open_palette", _params, socket), do: {:noreply, assign(socket, :palette_open, true)}

  @impl true
  def handle_info(:palette_closed, socket) do
    socket = socket |> assign(:palette_open, false) |> update(:close_count, &(&1 + 1))
    {:noreply, socket}
  end

  def handle_info({:palette_selected, result}, socket) do
    socket = socket |> assign(:selected_result, result) |> assign(:palette_open, false)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <button type="button" phx-click="open_palette">Open palette</button>
    <p id="close-count">{@close_count}</p>
    <p :if={@selected_result != :none} id="palette-selection">
      {if @selected_result, do: @selected_result.label, else: "cleared"}
    </p>
    <Flicker.palette
      id="cmdk"
      source={{Flicker.Providers.Static, results: @results}}
      open={@palette_open}
      on_close={if @silent, do: nil, else: :palette_closed}
      on_select={if @silent, do: nil, else: :palette_selected}
    />
    """
  end
end
