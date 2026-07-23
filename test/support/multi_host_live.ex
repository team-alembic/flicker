defmodule Flicker.Test.MultiHostLive do
  @moduledoc """
  A minimal host `LiveView` for driving `Flicker.select/1 multiple` with
  PhoenixTest (Spec 002).

  Two modes, chosen by the `"mode"` session key set by the test:

    * `"form"` — renders `Flicker.select/1` inside a `<.form>` in
      form-field mode, plus a submit button, so tests can exercise `name[]`
      array params, the array `_unused_` marker, and edit-form recovery via
      `"initial_values"`.
    * `"controlled"` (default) — renders it in controlled mode with
      `on_select`, so tests can exercise `handle_info/2` receiving the full
      selection list.

  Backed by `Flicker.Providers.Static` (overridable via the `"provider"`
  session key, e.g. a call-counting provider) so tests run with no Ash data
  layer at all.
  """

  use Phoenix.LiveView

  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
    %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
    %Flicker.Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"},
    %Flicker.Result{value: "4", label: "Riley Chen", sublabel: "Guitar"}
  ]

  @impl true
  def mount(_params, session, socket) do
    mode = Map.get(session, "mode", "controlled")
    initial_values = Map.get(session, "initial_values")
    provider = Map.get(session, "provider", {Flicker.Providers.Static, results: @results})
    max_selections = Map.get(session, "max_selections")

    # As with the single-select fixture: a fresh (non-submitted) form has no
    # `worker_ids` key at all — only seed one when simulating an edit form
    # with existing values.
    initial_params = if initial_values, do: %{"worker_ids" => initial_values}, else: %{}

    socket =
      socket
      |> assign(:mode, mode)
      |> assign(:provider, provider)
      |> assign(:max_selections, max_selections)
      |> assign(:selected_results, [])
      |> assign(:submitted_params, nil)
      |> assign(:form, to_form(initial_params, as: "form"))

    {:ok, socket}
  end

  @impl true
  def handle_info({:workers_selected, results}, socket) do
    {:noreply, assign(socket, :selected_results, results)}
  end

  # Merges the multi-select's array selection into the form's existing raw
  # params, mirroring `Flicker.Test.HostLive`'s single-value merge (extraction
  # notes #2) — the `_unused_` marker for the field is dropped once real
  # values arrive.
  def handle_info({Flicker.Components.Select, :selected, "form[worker_ids]", values}, socket) do
    params =
      (socket.assigns.form.source || %{})
      |> Map.put("worker_ids", values)
      |> Map.delete("_unused_worker_ids")

    {:noreply, assign(socket, :form, to_form(params, as: "form"))}
  end

  @impl true
  def handle_event("submit", %{"form" => params}, socket) do
    {:noreply, assign(socket, :submitted_params, params)}
  end

  @impl true
  def render(%{mode: "form"} = assigns) do
    ~H"""
    <.form for={@form} id="host-form" phx-submit="submit">
      <Flicker.select
        id="picker"
        field={@form[:worker_ids]}
        source={@provider}
        multiple
        max_selections={@max_selections}
      />
      <button type="submit">Submit</button>
    </.form>
    <p :if={@submitted_params} id="submitted">{inspect(@submitted_params)}</p>
    """
  end

  def render(%{mode: "stack"} = assigns) do
    ~H"""
    <Flicker.select id="picker" source={@provider} multiple max_visible={2} on_select={:workers_selected}>
      <:selected :let={result}><span data-avatar>{result.label}</span></:selected>
    </Flicker.select>
    <p id="selection">{inspect(Enum.map(@selected_results, & &1.label))}</p>
    """
  end

  def render(assigns) do
    ~H"""
    <Flicker.select
      id="picker"
      source={@provider}
      multiple
      max_selections={@max_selections}
      on_select={:workers_selected}
    />
    <p id="selection">{inspect(Enum.map(@selected_results, & &1.label))}</p>
    """
  end
end
