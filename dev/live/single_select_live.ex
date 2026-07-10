defmodule Dev.Live.SingleSelect do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1` in form-field mode and
  controlled mode, side by side, both reading `Dev.Music.Artist` — the
  seeded domain's policy-bearing resource. An actor toggle switches who's
  searching, so the label-based visibility policy is visibly exercised.
  """

  use Phoenix.LiveView

  alias Dev.Music.Artist

  @actors [
    {"Public (no label)", nil},
    {"Indie label", "indie"},
    {"Major label", "major"}
  ]

  @impl true
  @doc "Seeds `Dev.Music` (private ETS, scoped to this LiveView process) and sets up both picker's state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:actors, @actors)
      |> assign(:actor_label, nil)
      |> assign(:selected_result, :none)
      |> assign(:form, to_form(%{}, as: "artist"))

    {:ok, socket}
  end

  @impl true
  @doc "Switches the acting actor's `:label`, changing which artists are visible."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_actor", %{"label" => label}, socket) do
    {:noreply, assign(socket, :actor_label, normalize_label(label))}
  end

  defp normalize_label(""), do: nil
  defp normalize_label(label), do: label

  @impl true
  @doc "Receives the controlled-mode picker's selection."
  @spec handle_info({atom(), Flicker.Result.t() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:controlled_selected, result}, socket) do
    {:noreply, assign(socket, :selected_result, result)}
  end

  @impl true
  @doc "Renders the actor toggle and both pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns = assign(assigns, :actor, %{label: assigns.actor_label})

    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-semibold">Single select</h1>
      <p class="text-sm text-gray-600">
        Both pickers read <code>Dev.Music.Artist</code>, the policy-bearing
        resource — switch the actor and watch labelled artists appear or
        disappear from search results.
      </p>

      <fieldset class="flex flex-wrap items-center gap-2">
        <legend class="mb-1 text-sm font-medium">Acting as</legend>
        <button
          :for={{name, label} <- @actors}
          type="button"
          phx-click="set_actor"
          phx-value-label={label || ""}
          class={[
            "rounded px-3 py-1 text-sm",
            if(@actor_label == label, do: "bg-indigo-600 text-white", else: "bg-gray-200")
          ]}
        >
          {name}
        </button>
      </fieldset>

      <div class="grid grid-cols-1 gap-8 md:grid-cols-2">
        <section>
          <h2 class="mb-2 font-medium">Form mode</h2>
          <.form for={@form} id="artist-form">
            <Flicker.select
              id="artist-form-select"
              field={@form[:artist_id]}
              resource={Artist}
              actor={@actor}
              search={[:name]}
              option_label={:name}
              option_sublabel={fn artist -> artist.label || "public" end}
            />
          </.form>
        </section>

        <section>
          <h2 class="mb-2 font-medium">Controlled mode</h2>
          <Flicker.select
            id="artist-controlled-select"
            resource={Artist}
            actor={@actor}
            search={[:name]}
            option_label={:name}
            option_sublabel={fn artist -> artist.label || "public" end}
            on_select={:controlled_selected}
          />
          <p :if={@selected_result != :none} class="mt-2 text-sm">
            Selected: {if @selected_result, do: @selected_result.label, else: "cleared"}
          </p>
        </section>
      </div>
    </div>
    """
  end
end
