defmodule Dev.Live.KeyboardActivation do
  @moduledoc """
  Playground page (Spec 006): `activate_with_keyboard="mod+k"` on a search
  over `Dev.Music.Artist` — press Cmd+K on macOS or Ctrl+K elsewhere from
  anywhere on this page to focus and open it, even while typing in the
  plain text input alongside it. A second, identically-chorded select
  further down demonstrates the duplicate-chord console warning (open the
  browser console): the first registration wins, the second stays inert.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Music.Artist

  @impl true
  @doc "Seeds `Dev.Music` and assigns both pickers' state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:selected_result, :none)
      |> assign(:duplicate_selected_result, :none)

    {:ok, socket}
  end

  @impl true
  @doc "Receives whichever select's controlled-mode selection fired."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:keyboard_selected, result}, socket) do
    {:noreply, assign(socket, :selected_result, result)}
  end

  def handle_info({:keyboard_duplicate_selected, result}, socket) do
    {:noreply, assign(socket, :duplicate_selected_result, result)}
  end

  @impl true
  @doc "Renders an unrelated text input (proving the chord fires while it's focused) and both selects."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.page
      title="Keyboard activation"
      current_path="/keyboard-activation"
      spec="docs/specs/spec-006-keyboard-activation.md"
    >
      <:description>
        Press <kbd class="rounded border border-gray-300 px-1.5 py-0.5 text-xs">⌘K</kbd>
        / <kbd class="rounded border border-gray-300 px-1.5 py-0.5 text-xs">Ctrl+K</kbd>
        anywhere on this page to jump into the search below — including
        while the unrelated text field underneath has focus.
      </:description>

      <div>
        <label class="mb-1 block text-sm font-medium text-gray-700" for="unrelated-input">
          An unrelated text input (click in here, then press the chord)
        </label>
        <input id="unrelated-input" type="text" class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm" />
      </div>

      <.section label="mod+k search">
        <Flicker.select
          id="keyboard-select"
          resource={Artist}
          search={[:name]}
          option_label={:name}
          on_select={:keyboard_selected}
          activate_with_keyboard="mod+k"
        />
        <p :if={@selected_result != :none} class="mt-2 text-sm text-gray-700">
          Selected: {if @selected_result, do: @selected_result.label, else: "cleared"}
        </p>
      </.section>

      <.section label="A second mod+k search (duplicate chord)">
        <p class="mb-2 text-sm text-gray-600">
          Claims the same chord as the one above — check the console for
          the duplicate-registration warning; the chord above keeps
          winning, this one only activates by clicking into it directly.
        </p>
        <Flicker.select
          id="keyboard-duplicate-select"
          resource={Artist}
          search={[:name]}
          option_label={:name}
          on_select={:keyboard_duplicate_selected}
          activate_with_keyboard="mod+k"
        />
        <p :if={@duplicate_selected_result != :none} class="mt-2 text-sm text-gray-700">
          Selected: {if @duplicate_selected_result, do: @duplicate_selected_result.label, else: "cleared"}
        </p>
      </.section>
    </.page>
    """
  end
end
