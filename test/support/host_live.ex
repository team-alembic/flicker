defmodule Flicker.Test.HostLive do
  @moduledoc """
  A minimal host `LiveView` for driving `Flicker.select/1` with PhoenixTest.

  Not part of the public API — test-support only (`test/support`). Two
  modes, chosen by the `"mode"` session key set by the test:

    * `"form"` — renders `Flicker.select/1` inside a `<.form>` in
      form-field mode, plus a submit button, so tests can exercise the
      `_unused_` marker, required-field-error suppression, and submitted
      params.
    * `"controlled"` (default) — renders it in controlled mode with
      `on_select`, so tests can exercise `handle_info/2` selection.

  Backed by `Flicker.Providers.Static` with a small fixed result set so
  tests run with no Ash data layer at all. The `"activate_with_keyboard"`
  session key (controlled mode only) passes a chord straight through to
  `Flicker.select/1`, for exercising Spec 006's server-side validation and
  rendering. The `"facets"` session key (controlled mode only) passes a
  hand-built `Flicker.Facet` list straight through, for exercising Spec
  003's faceted-search behaviour with no Ash resource involved. The
  `"paginate"`, `"max_windows"`, and `"limit"` session keys (controlled
  mode only) pass straight through to `Flicker.select/1`, for exercising
  Spec 010's windowed search.
  """

  use Phoenix.LiveView

  # String values, like a real form always delivers (and like an Ash
  # primary key typically is) — this fixture would mask a broken
  # string-comparison selected-value resolution otherwise (extraction notes
  # #4) if it used bare integers.
  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
    %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
    %Flicker.Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"}
  ]

  @impl true
  def mount(_params, session, socket) do
    mode = Map.get(session, "mode", "controlled")
    initial_value = Map.get(session, "initial_value")
    provider = Map.get(session, "provider", {Flicker.Providers.Static, results: @results})
    min_chars = Map.get(session, "min_chars", 0)
    activate_with_keyboard = Map.get(session, "activate_with_keyboard")
    facets = Map.get(session, "facets", [])
    paginate = Map.get(session, "paginate", false)
    max_windows = Map.get(session, "max_windows")
    limit = Map.get(session, "limit")

    # A fresh (non-submitted) form has no `client_id` key in its params at
    # all — only seed one when the test is simulating an edit form with an
    # existing value, so the required-field-not-yet-engaged case isn't
    # accidentally pre-populated into "used".
    initial_params = if initial_value, do: %{"client_id" => initial_value}, else: %{}

    socket =
      socket
      |> assign(:mode, mode)
      |> assign(:provider, provider)
      |> assign(:min_chars, min_chars)
      |> assign(:activate_with_keyboard, activate_with_keyboard)
      |> assign(:facets, facets)
      |> assign(:paginate, paginate)
      |> assign(:max_windows, max_windows)
      |> assign(:limit, limit)
      |> assign(:selected_result, :none)
      |> assign(:submitted_params, nil)
      |> assign(:form, to_form(initial_params, as: "form"))

    {:ok, socket}
  end

  @impl true
  def handle_info({:client_selected, result}, socket) do
    {:noreply, assign(socket, :selected_result, result)}
  end

  # Applies a form-field-mode selection: merges into the form's existing
  # raw params rather than replacing them, so other fields' in-progress
  # state (and their own `_unused_` markers) survive (extraction notes #2).
  # `Flicker.AshPhoenixForm.attach/2` is the shipped adapter for hosts using
  # `AshPhoenix.Form`; this is the same mechanic for a plain Phoenix form.
  def handle_info({Flicker.Components.Select, :selected, "form[client_id]", value}, socket) do
    params =
      (socket.assigns.form.source || %{})
      |> Map.put("client_id", value)
      |> Map.delete("_unused_client_id")

    {:noreply, assign(socket, :form, to_form(params, as: "form"))}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = to_form(params, as: "form", errors: form_errors(params))
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"form" => params}, socket) do
    {:noreply, assign(socket, :submitted_params, params)}
  end

  defp form_errors(%{"client_id" => value}) when value in [nil, ""], do: [client_id: {"can't be blank", []}]

  defp form_errors(_params), do: []

  @impl true
  def render(%{mode: "both"} = assigns) do
    ~H"""
    <.form for={@form} id="host-form">
      <Flicker.select id="picker" field={@form[:client_id]} source={@provider} on_select={:client_selected} />
    </.form>
    <p :if={@selected_result != :none} id="selection">
      {if @selected_result, do: @selected_result.label, else: "cleared"}
    </p>
    """
  end

  def render(%{mode: "neither"} = assigns) do
    ~H"""
    <Flicker.select id="picker" source={@provider} />
    """
  end

  def render(%{mode: "form"} = assigns) do
    ~H"""
    <.form for={@form} id="host-form" phx-change="validate" phx-submit="submit">
      <Flicker.select id="picker" field={@form[:client_id]} source={@provider} required={true} />
      <p :if={Phoenix.Component.used_input?(@form[:client_id])} id="client-id-error">
        <span :for={{message, _opts} <- @form[:client_id].errors}>{message}</span>
      </p>
      <button type="submit">Submit</button>
    </.form>
    <p :if={@submitted_params} id="submitted">{inspect(@submitted_params)}</p>
    """
  end

  def render(assigns) do
    ~H"""
    <Flicker.select
      id="picker"
      source={@provider}
      min_chars={@min_chars}
      limit={@limit}
      on_select={:client_selected}
      activate_with_keyboard={@activate_with_keyboard}
      facets={@facets}
      paginate={@paginate}
      max_windows={@max_windows}
    />
    <p :if={@selected_result != :none} id="selection">
      {if @selected_result, do: @selected_result.label, else: "cleared"}
    </p>
    """
  end
end
