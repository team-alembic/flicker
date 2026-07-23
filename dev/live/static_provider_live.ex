defmodule Dev.Live.StaticProvider do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1` against
  `Flicker.Providers.Static` — the pure-Elixir, no-Ash path — proving the
  provider contract stands alone in a place humans can poke at.
  """

  use Phoenix.LiveView

  import Dev.UI

  @results [
    %Flicker.Result{value: "mercury", label: "Mercury", sublabel: "1st planet"},
    %Flicker.Result{value: "venus", label: "Venus", sublabel: "2nd planet"},
    %Flicker.Result{value: "earth", label: "Earth", sublabel: "3rd planet"},
    %Flicker.Result{value: "mars", label: "Mars", sublabel: "4th planet"},
    %Flicker.Result{value: "jupiter", label: "Jupiter", sublabel: "5th planet"},
    %Flicker.Result{value: "saturn", label: "Saturn", sublabel: "6th planet"},
    %Flicker.Result{value: "uranus", label: "Uranus", sublabel: "7th planet"},
    %Flicker.Result{value: "neptune", label: "Neptune", sublabel: "8th planet"}
  ]

  @impl true
  @doc "Assigns the fixed result list; no Ash domain involved."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:results, @results)
      |> assign(:selected_result, :none)

    {:ok, socket}
  end

  @impl true
  @doc "Receives the picker's selection."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:planet_selected, result}, socket) do
    {:noreply, assign(socket, :selected_result, result)}
  end

  @impl true
  @doc "Renders the picker."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assign(assigns, :example_code, ~S"""
      <Flicker.select
        id="planet-select"
        source={{Flicker.Providers.Static, results: @results}}
        on_select={:planet_selected}
      />
      """)

    ~H"""
    <.page title="Pure-Elixir provider" current_path="/static-provider" spec="docs/specs/spec-004-provider-contract.md">
      <:description>
        No Ash resource here — <code>Flicker.Providers.Static</code>
        over a fixed in-memory list.
      </:description>

      <.section label="Static provider">
        <.code_example id="static-provider-code" code={@example_code}>
          <Flicker.select
            id="planet-select"
            source={{Flicker.Providers.Static, results: @results}}
            on_select={:planet_selected}
          />
        </.code_example>
        <p :if={@selected_result != :none} class="mt-2 text-sm text-gray-700">
          Selected: {if @selected_result, do: @selected_result.label, else: "cleared"}
        </p>
      </.section>
    </.page>
    """
  end
end
