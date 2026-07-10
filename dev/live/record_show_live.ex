defmodule Dev.Live.RecordShow do
  @moduledoc """
  The navigate-on-select destination (Spec 008): `Dev.Providers.MusicSearch`
  sets `meta.href` to `/records/:type/:id` on every result, so selecting
  one in the `/palette` demo `push_navigate`s here — proving the palette's
  navigate-on-select convention actually lands somewhere.
  """

  use Phoenix.LiveView

  @impl true
  @doc "Assigns the `:type`/`:id` path params straight through — nothing to load, this page only proves navigation happened."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"type" => type, "id" => id}, _session, socket) do
    {:ok, assign(socket, type: type, id: id)}
  end

  @impl true
  @doc "Renders confirmation of which record the palette navigated to."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold">Navigated via the palette</h1>
      <p class="text-sm text-gray-600">
        Selecting a result with <code>meta.href</code> set issued a
        <code>push_navigate/2</code> straight here — no <code>on_select</code>
        handling required on the host's part.
      </p>
      <p id="record-summary" class="rounded-md border border-gray-200 px-3 py-2 text-sm">
        Type: <strong>{@type}</strong> · Id: <code>{@id}</code>
      </p>
      <.link navigate="/palette" class="text-indigo-600 hover:underline">Back to the palette demo</.link>
    </div>
    """
  end
end
