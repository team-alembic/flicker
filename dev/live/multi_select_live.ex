defmodule Dev.Live.MultiSelect do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1 multiple` in form-field mode
  and controlled mode, side by side, both reading `Dev.Music.Artist` —
  exercises Spec 002's chips, `max_selections` cap, and batch `fetch/2`
  label resolution (an edit-form picker mounts with three artists
  preselected).
  """

  use Phoenix.LiveView

  alias Dev.Music.Artist

  @impl true
  @doc "Seeds `Dev.Music` and preselects three artists on the form-mode picker, so batch `fetch/2` resolution is visible on load."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    %{artists: artists} = Dev.Music.seed!()
    preselected_ids = artists |> Enum.take(3) |> Enum.map(& &1.id)

    socket =
      socket
      |> assign(:selected_results, [])
      |> assign(:form, to_form(%{"artist_ids" => preselected_ids}, as: "artists"))

    {:ok, socket}
  end

  @impl true
  @doc "Receives the controlled-mode picker's full selection list on every change."
  @spec handle_info({atom(), [Flicker.Result.t()]}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:controlled_selected, results}, socket) do
    {:noreply, assign(socket, :selected_results, results)}
  end

  @impl true
  @doc "Renders both pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-semibold">Multi-select</h1>
      <p class="text-sm text-gray-600">
        Both pickers read <code>Dev.Music.Artist</code>. The form-mode picker
        opens with three artists preselected — one <code>fetch/2</code> call
        resolves all three chips. The controlled picker caps at 4 selections.
      </p>

      <div class="grid grid-cols-1 gap-8 md:grid-cols-2">
        <section>
          <h2 class="mb-2 font-medium">Form mode (preselected)</h2>
          <.form for={@form} id="artists-form">
            <Flicker.select
              id="artist-form-multiselect"
              field={@form[:artist_ids]}
              multiple
              resource={Artist}
              search={[:name]}
              option_label={:name}
              option_sublabel={fn artist -> artist.label || "public" end}
            />
          </.form>
        </section>

        <section>
          <h2 class="mb-2 font-medium">Controlled mode (max 4)</h2>
          <Flicker.select
            id="artist-controlled-multiselect"
            resource={Artist}
            multiple
            max_selections={4}
            search={[:name]}
            option_label={:name}
            option_sublabel={fn artist -> artist.label || "public" end}
            on_select={:controlled_selected}
          />
          <p class="mt-2 text-sm">
            Selected: {@selected_results |> Enum.map(& &1.label) |> Enum.join(", ")}
          </p>
        </section>
      </div>
    </div>
    """
  end
end
