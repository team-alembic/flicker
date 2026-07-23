defmodule Dev.Live.Palette do
  @moduledoc """
  Playground page (Spec 008): `Flicker.palette/1` federated over the whole
  `Dev.Music` domain via `Dev.Providers.MusicSearch` — Artists, Albums, and
  Genres in one ⌘K search, grouped by resource. Press `mod+k` anywhere on
  this page, or click the navbar-style trigger button (the `open`/
  `on_close` controlled API); selecting a result navigates to
  `/records/:type/:id` (navigate-on-select, `meta.href`).

  Also exercises `facets` inside `Flicker.palette/1` end-to-end (Spec
  008's now-closed open question) — `Dev.Providers.MusicSearch.facets/0`
  supplies `status:`/`type:` key/value autocomplete, and its `search/2`
  honours both (see that module's moduledoc).
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Providers.MusicSearch

  # The public actor (no `:label`) — `Dev.Music.Artist`'s policy is
  # actor-scoped (see its moduledoc), so a demo actor is needed here for
  # artist results to come back at all, same as every other Ash-backed
  # playground page.
  @actor %{label: nil}

  @impl true
  @doc "Seeds `Dev.Music` and assigns the overlay's controlled `open` state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:palette_open, false)
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
  @doc "Renders the trigger button and the palette."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assign(assigns, :example_code, ~S"""
      <button type="button" phx-click="open_palette">
        Open command palette
      </button>
      <Flicker.palette
        id="cmdk"
        source={MyApp.Providers.MusicSearch}
        open={@palette_open}
        on_close={:palette_closed}
        on_select={:palette_selected}
      />
      """)

    ~H"""
    <.page title="Command palette" current_path="/palette" spec="docs/specs/spec-008-command-palette.md">
      <:description>
        Federated search over Artists, Albums, and Genres — press
        <kbd class="rounded border border-gray-300 px-1.5 py-0.5 text-xs">⌘K</kbd>
        / <kbd class="rounded border border-gray-300 px-1.5 py-0.5 text-xs">Ctrl+K</kbd>,
        or click the button below. Try <code>status:active</code> or
        <code>type:album</code> for faceted narrowing.
      </:description>

      <.code_example id="palette-code" code={@example_code}>
        <button
          id="cmdk-open-trigger"
          type="button"
          phx-click="open_palette"
          class="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-600 hover:bg-gray-50"
        >
          Open command palette
        </button>
        <Flicker.palette
          id="cmdk"
          source={MusicSearch}
          actor={@actor}
          open={@palette_open}
          on_close={:palette_closed}
          on_select={:palette_selected}
        />
      </.code_example>
    </.page>
    """
  end
end
