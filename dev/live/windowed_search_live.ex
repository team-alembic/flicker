defmodule Dev.Live.WindowedSearch do
  @moduledoc """
  Playground page ([Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md)):
  `paginate` over a population large enough to make scrolling meaningful —
  one picker against `Flicker.Providers.AshResource` (`Dev.Music.Artist`,
  seeded to 220 rows instead of the usual 50), and one against
  `Dev.Providers.Slow` wrapping a large `Flicker.Providers.Static` list,
  latency adjustable, so the themed loading-more row and `aria-busy` are
  easy to see land.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Music.Artist
  alias Dev.Providers.Slow

  @artist_count 220
  @static_count 150

  @impl true
  @doc "Seeds `Dev.Music` with a larger-than-usual artist population and builds the slow provider's static list."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!(@artist_count)

    results =
      for i <- 1..@static_count do
        %Flicker.Result{value: i, label: "Constellation #{i}", sublabel: "Star cluster ##{i}"}
      end

    socket =
      socket
      |> assign(:results, results)
      |> assign(:latency_ms, 400)
      |> assign(:selected_artist, :none)
      |> assign(:selected_constellation, :none)

    {:ok, socket}
  end

  @impl true
  @doc "Updates the slow provider's configured latency from the form input."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_latency", %{"latency_ms" => latency_ms}, socket) do
    {:noreply, assign(socket, :latency_ms, parse_latency(latency_ms))}
  end

  defp parse_latency(value) do
    case Integer.parse(value) do
      {ms, _rest} when ms >= 0 -> ms
      _invalid -> 400
    end
  end

  @impl true
  @doc "Receives either picker's selection."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:artist_selected, result}, socket), do: {:noreply, assign(socket, :selected_artist, result)}

  def handle_info({:constellation_selected, result}, socket),
    do: {:noreply, assign(socket, :selected_constellation, result)}

  @impl true
  @doc "Renders both windowed pickers and the slow provider's latency control."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assigns
      |> assign(:artist_code, ~S"""
      <Flicker.select
        id="artist-windowed-select"
        resource={MyApp.Music.Artist}
        search={[:name]}
        option_label={:name}
        option_sublabel={fn artist -> "formed #{artist.formed_on.year}" end}
        on_select={:artist_selected}
        theme={Flicker.Theme.tailwind()}
        paginate
      />
      """)
      |> assign(:constellation_code, ~S"""
      <Flicker.select
        id="constellation-windowed-select"
        source={{MyApp.Providers.Slow, results: @results, latency_ms: @latency_ms}}
        on_select={:constellation_selected}
        theme={Flicker.Theme.tailwind()}
        paginate
      />
      """)

    ~H"""
    <.page title="Windowed search" current_path="/windowed-search" spec="docs/specs/spec-010-windowed-search.md">
      <:description>
        <code>paginate</code> replaces "keep typing to narrow" with infinite
        scroll — scroll the listbox to its tail (or press <kbd>↓</kbd> on the
        last option) to load the next window.
      </:description>

      <.section label="Fast — Flicker.Providers.AshResource">
        <p class="mb-3 text-sm text-gray-600">
          220 seeded <code>Dev.Music.Artist</code> rows, offset via
          <code>Ash.Query.offset/2</code>.
        </p>
        <%!--
          Both pickers on this page use the Tailwind preset: infinite
          scroll needs a listbox that actually scrolls (`max-h-60
          overflow-auto`), which the unstyled vanilla default can't give
          it — an unconstrained listbox just grows, and the tail sentinel
          never has a fold to cross.
        --%>
        <.code_example id="windowed-artist-code" code={@artist_code}>
          <Flicker.select
            id="artist-windowed-select"
            resource={Artist}
            actor={%{label: nil}}
            search={[:name]}
            option_label={:name}
            option_sublabel={fn artist -> "formed #{artist.formed_on.year}" end}
            on_select={:artist_selected}
            theme={Flicker.Theme.tailwind()}
            paginate
          />
        </.code_example>
        <p :if={@selected_artist != :none} class="mt-2 text-sm text-gray-700">
          Selected: {if @selected_artist, do: @selected_artist.label, else: "cleared"}
        </p>
      </.section>

      <.section label="Slow — Dev.Providers.Slow wrapping Static">
        <p class="mb-3 text-sm text-gray-600">
          150 in-memory results, offset via <code>Enum.slice/3</code>;
          latency makes the loading-more row and <code>aria-busy</code> easy to see land.
        </p>
        <form phx-change="set_latency" class="mb-3 flex items-center gap-2 text-sm text-gray-700">
          <label for="windowed-latency_ms">Latency (ms)</label>
          <input
            type="number"
            name="latency_ms"
            id="windowed-latency_ms"
            value={@latency_ms}
            min="0"
            step="100"
            class="w-24 rounded-md border border-gray-300 px-2 py-1"
          />
        </form>
        <.code_example id="windowed-constellation-code" code={@constellation_code}>
          <Flicker.select
            id="constellation-windowed-select"
            source={{Slow, results: @results, latency_ms: @latency_ms}}
            on_select={:constellation_selected}
            theme={Flicker.Theme.tailwind()}
            paginate
          />
        </.code_example>
        <p :if={@selected_constellation != :none} class="mt-2 text-sm text-gray-700">
          Selected: {if @selected_constellation, do: @selected_constellation.label, else: "cleared"}
        </p>
      </.section>
    </.page>
    """
  end
end
