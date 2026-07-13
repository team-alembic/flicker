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
    ~H"""
    <div class="space-y-8">
      <h1 class="text-2xl font-semibold">Windowed search</h1>
      <p class="text-sm text-gray-600">
        <code>paginate</code> replaces "keep typing to narrow" with infinite
        scroll — scroll the listbox to its tail (or press <kbd>↓</kbd> on the
        last option) to load the next window. See
        <a
          class="text-indigo-600 hover:underline"
          href="https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md"
        >
          Spec 010
        </a>.
      </p>

      <section>
        <h2 class="mb-2 font-medium">Fast — <code>Flicker.Providers.AshResource</code></h2>
        <p class="mb-2 text-sm text-gray-600">
          220 seeded <code>Dev.Music.Artist</code> rows, offset via
          <code>Ash.Query.offset/2</code>.
        </p>
        <Flicker.select
          id="artist-windowed-select"
          resource={Artist}
          actor={%{label: nil}}
          search={[:name]}
          option_label={:name}
          option_sublabel={fn artist -> artist.label || "public" end}
          on_select={:artist_selected}
          paginate
        />
        <p :if={@selected_artist != :none} class="mt-2 text-sm">
          Selected: {if @selected_artist, do: @selected_artist.label, else: "cleared"}
        </p>
      </section>

      <section>
        <h2 class="mb-2 font-medium">Slow — <code>Dev.Providers.Slow</code> wrapping <code>Static</code></h2>
        <p class="mb-2 text-sm text-gray-600">
          150 in-memory results, offset via <code>Enum.slice/3</code>;
          latency makes the loading-more row and <code>aria-busy</code> easy to see land.
        </p>
        <form phx-change="set_latency" class="mb-2 flex items-center gap-2 text-sm">
          <label for="windowed-latency_ms">Latency (ms)</label>
          <input type="number" name="latency_ms" id="windowed-latency_ms" value={@latency_ms} min="0" step="100" />
        </form>
        <Flicker.select
          id="constellation-windowed-select"
          source={{Slow, results: @results, latency_ms: @latency_ms}}
          on_select={:constellation_selected}
          paginate
        />
        <p :if={@selected_constellation != :none} class="mt-2 text-sm">
          Selected: {if @selected_constellation, do: @selected_constellation.label, else: "cleared"}
        </p>
      </section>
    </div>
    """
  end
end
