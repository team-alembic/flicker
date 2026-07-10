defmodule Dev.Live.EdgeStates do
  @moduledoc """
  Playground page (Spec 005): edge states reproducible on demand — a
  configurable-latency slow provider (loading / debounce / stale-result
  drop), an always-erroring provider, and a guaranteed-empty result set.
  """

  use Phoenix.LiveView

  alias Dev.Providers.{Erroring, Slow}

  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy"},
    %Flicker.Result{value: "2", label: "Alex Rivers"},
    %Flicker.Result{value: "3", label: "Jordan Blake"}
  ]

  @impl true
  @doc "Assigns the fixed result list and the default slow-provider latency (1000ms)."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:results, @results)
      |> assign(:latency_ms, 1_000)

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
      _invalid -> 1_000
    end
  end

  @impl true
  @doc "No-op: this page demonstrates loading/error/empty states, not a selection outcome."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:noop_selected, _result}, socket), do: {:noreply, socket}

  @impl true
  @doc "Renders the latency control and the three edge-state pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <h1 class="text-2xl font-semibold">Edge states</h1>

      <section>
        <h2 class="mb-2 font-medium">Slow provider (loading / debounce / stale-drop)</h2>
        <form phx-change="set_latency" class="mb-2 flex items-center gap-2 text-sm">
          <label for="latency_ms">Latency (ms)</label>
          <input type="number" name="latency_ms" id="latency_ms" value={@latency_ms} min="0" step="100" />
        </form>
        <Flicker.select
          id="slow-select"
          source={{Slow, results: @results, latency_ms: @latency_ms}}
          on_select={:noop_selected}
        />
      </section>

      <section>
        <h2 class="mb-2 font-medium">Erroring provider</h2>
        <Flicker.select id="erroring-select" source={Erroring} on_select={:noop_selected} />
      </section>

      <section>
        <h2 class="mb-2 font-medium">Empty results</h2>
        <Flicker.select
          id="empty-select"
          source={{Flicker.Providers.Static, results: []}}
          on_select={:noop_selected}
        />
      </section>
    </div>
    """
  end
end
