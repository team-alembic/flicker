defmodule Dev.Live.PaletteThemed do
  @moduledoc """
  Playground page (Spec 008): the exact same `Flicker.palette/1` +
  `Dev.Providers.MusicSearch` federated search as `/palette`, restyled to a
  fullscreen, on-brand look purely via a `theme` override — proving the
  overlay's chrome parts (`:backdrop`, `:panel`, `:palette_input`,
  `:group_header`, `:footer`) are a class-map exercise, not a fork.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Providers.MusicSearch

  @brand_theme %{
    backdrop: "fixed inset-0 z-40 bg-slate-950",
    panel: "fixed inset-0 z-50 mx-auto flex max-w-3xl flex-col px-6 pt-24",
    palette_input:
      "w-full border-0 border-b-2 border-slate-700 bg-transparent px-0 py-4 text-3xl text-white " <>
        "placeholder:text-slate-500 focus:border-emerald-400 focus:outline-none",
    listbox: "mt-4 max-h-[60vh] overflow-auto",
    option: "cursor-pointer rounded-md px-3 py-2 text-slate-200 hover:bg-slate-800",
    option_active: "bg-emerald-600 text-white",
    group_header: "px-3 py-2 text-xs font-semibold uppercase tracking-widest text-emerald-400",
    footer: "mt-auto flex items-center gap-4 border-t border-slate-800 py-4 text-xs text-slate-500",
    kbd_hint: "rounded border border-slate-700 px-1.5 text-slate-400",
    footer_hint: "rounded border border-slate-700 px-1.5 text-slate-400",
    clear_button: "text-slate-400 hover:text-white",
    palette_close: "text-slate-400 hover:text-white"
  }

  # The public actor (no `:label`) — same reasoning as `Dev.Live.Palette`.
  @actor %{label: nil}

  @impl true
  @doc "Seeds `Dev.Music` and assigns the overlay's controlled `open` state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:palette_open, false)
      |> assign(:brand_theme, @brand_theme)
      |> assign(:actor, @actor)

    {:ok, socket}
  end

  @impl true
  @doc "The navbar-style trigger button."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("open_palette", _params, socket), do: {:noreply, assign(socket, :palette_open, true)}

  @impl true
  @doc "The palette's `on_close`/`on_select` controlled-mode messages."
  @spec handle_info(atom() | {atom(), Flicker.Result.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:palette_closed, socket), do: {:noreply, assign(socket, :palette_open, false)}

  def handle_info({:palette_selected, _result}, socket), do: {:noreply, assign(socket, :palette_open, false)}

  @impl true
  @doc "Renders the trigger button and the restyled palette."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.page title="Command palette — themed" current_path="/palette-themed" spec="docs/specs/spec-008-command-palette.md">
      <:description>
        The same <code>Flicker.palette/1</code> + federated provider as
        <.link navigate="/palette" class="text-indigo-600 underline">/palette</.link>
        — restyled fullscreen and on-brand with nothing but a
        <code>theme</code> override map.
      </:description>

      <button
        type="button"
        phx-click="open_palette"
        class="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-600 hover:bg-gray-50"
      >
        Open themed command palette
      </button>
      <Flicker.palette
        id="cmdk-themed"
        source={MusicSearch}
        actor={@actor}
        open={@palette_open}
        on_close={:palette_closed}
        on_select={:palette_selected}
        theme={@brand_theme}
        activate_with_keyboard="mod+k"
      />
    </.page>
    """
  end
end
