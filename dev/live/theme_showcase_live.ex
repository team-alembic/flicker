defmodule Dev.Live.ThemeShowcase do
  @moduledoc """
  Playground page (Spec 005): the same `Flicker.select/1` (over
  `Flicker.Providers.Static`) rendered in every shipped theme preset —
  vanilla, Tailwind, and daisyUI — side by side.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Flicker.Theme

  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
    %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
    %Flicker.Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"}
  ]

  @presets [vanilla: Theme.vanilla(), tailwind: Theme.tailwind(), daisy_ui: Theme.daisy_ui()]

  # daisyUI's CDN build ships every built-in theme; toggling `data-theme`
  # on the demo's wrapper is all it takes for the daisyUI preset to adapt.
  @daisy_themes ~w(light dark cupcake corporate synthwave retro dracula nord)

  @impl true
  @doc "Assigns the fixed result list, every theme preset, and the daisyUI theme."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:results, @results)
      |> assign(:presets, @presets)
      |> assign(:daisy_themes, @daisy_themes)
      |> assign(:daisy_theme, "light")

    {:ok, socket}
  end

  @impl true
  @doc "Switches which daisyUI built-in theme the daisyUI preset demo renders under."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_daisy_theme", %{"theme" => theme}, socket) when theme in @daisy_themes do
    {:noreply, assign(socket, :daisy_theme, theme)}
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
    <.page title="Theme showcase" current_path="/themes">
      <:description>
        The same <code>Flicker.select/1</code> rendered in every shipped theme preset.
      </:description>

      <div class="grid grid-cols-1 gap-6 md:grid-cols-3">
        <.section :for={{name, theme} <- @presets} label={name |> to_string() |> String.replace("_", " ")}>
          <p class="mb-3 text-xs text-gray-400">{preset_blurb(name)}</p>
          <div :if={name == :daisy_ui} class="mb-3">
            <form phx-change="set_daisy_theme">
              <label for="daisy-theme-picker" class="mr-2 text-xs text-gray-500">daisyUI theme</label>
              <select
                id="daisy-theme-picker"
                name="theme"
                class="rounded-md border border-gray-300 px-2 py-1 text-sm"
              >
                <option :for={t <- @daisy_themes} value={t} selected={t == @daisy_theme}>{t}</option>
              </select>
            </form>
          </div>
          <div data-theme={if name == :daisy_ui, do: @daisy_theme} class={name == :daisy_ui && "rounded-lg bg-base-100 p-3"}>
            <Flicker.select
              id={"theme-select-#{name}"}
              source={{Flicker.Providers.Static, results: @results}}
              theme={theme}
              on_select={:theme_selected}
            />
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp preset_blurb(:vanilla), do: "Unstyled flicker-* class names — bring your own CSS. The library default."

  defp preset_blurb(:tailwind), do: "Tailwind utilities, no component library."

  defp preset_blurb(:daisy_ui), do: "daisyUI components — adapts to any built-in daisyUI theme. Try a few:"
end
