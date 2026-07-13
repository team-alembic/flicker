defmodule Dev.Live.RecordShow do
  @moduledoc """
  The navigate-on-select destination (Spec 008): `Dev.Providers.MusicSearch`
  sets `meta.href` to `/records/:type/:id` on every result, so selecting
  one in the `/palette` demo `push_navigate`s here — proving the palette's
  navigate-on-select convention actually lands somewhere.
  """

  use Phoenix.LiveView

  import Dev.UI

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
    <.page title="Navigated via the palette" current_path="/palette" spec="docs/specs/spec-008-command-palette.md">
      <:description>
        Selecting a result with <code>meta.href</code> set issued a
        <code>push_navigate/2</code> straight here — no <code>on_select</code>
        handling required on the host's part.
      </:description>

      <.section label="Destination">
        <p id="record-summary" class="text-sm text-gray-700">
          Type: <strong>{@type}</strong> · Id: <code>{@id}</code>
        </p>
        <.link navigate="/palette" class="mt-3 inline-block text-sm text-indigo-600 underline">
          Back to the palette demo
        </.link>
      </.section>
    </.page>
    """
  end
end
