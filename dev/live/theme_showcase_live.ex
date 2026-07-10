defmodule Dev.Live.ThemeShowcase do
  @moduledoc """
  Playground page (Spec 005): the same `Flicker.select/1` (over
  `Flicker.Providers.Static`) rendered in every shipped theme preset —
  vanilla, Tailwind, and daisyUI — side by side.
  """

  use Phoenix.LiveView

  alias Flicker.Theme

  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
    %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
    %Flicker.Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"}
  ]

  @presets [vanilla: Theme.vanilla(), tailwind: Theme.tailwind(), daisy_ui: Theme.daisy_ui()]

  @impl true
  @doc "Assigns the fixed result list and every theme preset."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:results, @results)
      |> assign(:presets, @presets)

    {:ok, socket}
  end

  @impl true
  @doc "No-op: this page doesn't track a selection, only rendering."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:theme_selected, _result}, socket), do: {:noreply, socket}

  @impl true
  @doc "Renders one picker per preset."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <h1 class="text-2xl font-semibold">Theme showcase</h1>
      <div class="grid grid-cols-1 gap-8 md:grid-cols-3">
        <section :for={{name, theme} <- @presets}>
          <h2 class="mb-2 font-medium capitalize">{name}</h2>
          <Flicker.select
            id={"theme-select-#{name}"}
            source={{Flicker.Providers.Static, results: @results}}
            theme={theme}
            on_select={:theme_selected}
          />
        </section>
      </div>
    </div>
    """
  end
end
