defmodule Dev.Live.SingleSelect do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1` in form-field mode and
  controlled mode, side by side, both reading `Dev.Music.Artist` — the
  seeded domain's policy-bearing resource. An actor toggle switches who's
  searching, so the label-based visibility policy is visibly exercised.
  """

  use Phoenix.LiveView

  import Dev.UI

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
  @doc "Receives the controlled-mode picker's selection, and applies the form-mode picker's."
  @spec handle_info(
          {atom(), Flicker.Result.t() | nil}
          | {module(), :selected, String.t(), String.t() | nil},
          Phoenix.LiveView.Socket.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:controlled_selected, result}, socket) do
    {:noreply, assign(socket, :selected_result, result)}
  end

  # Form-field mode notifies the host with the field's new value so it can
  # merge it into its own form params (the same mechanic
  # `Flicker.AshPhoenixForm.attach/2` ships for `AshPhoenix.Form` hosts).
  # Without this clause every form-mode selection crashed this LiveView —
  # caught by Spec 007's browser suite; PhoenixTest never drove this page,
  # only the test-support hosts (which do handle it).
  def handle_info({Flicker.Components.Select, :selected, "artist[artist_id]", value}, socket) do
    params =
      (socket.assigns.form.source || %{})
      |> Map.put("artist_id", value)
      |> Map.delete("_unused_artist_id")

    {:noreply, assign(socket, :form, to_form(params, as: "artist"))}
  end

  @impl true
  @doc "Renders the actor toggle and both pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns = assign(assigns, :actor, %{label: assigns.actor_label})

    ~H"""
    <.page title="Single select" current_path="/single-select" spec="docs/specs/spec-001-portable-single-select.md">
      <:description>
        Both pickers read <code>Dev.Music.Artist</code>, the policy-bearing
        resource — switch the actor and watch labelled artists appear or
        disappear from search results.
      </:description>

      <.actor_toggle actors={@actors} selected={@actor_label} />

      <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
        <.section label="Form mode">
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
        </.section>

        <.section label="Controlled mode">
          <Flicker.select
            id="artist-controlled-select"
            resource={Artist}
            actor={@actor}
            search={[:name]}
            option_label={:name}
            option_sublabel={fn artist -> artist.label || "public" end}
            on_select={:controlled_selected}
          />
          <p :if={@selected_result != :none} class="mt-2 text-sm text-gray-700">
            Selected: {if @selected_result, do: @selected_result.label, else: "cleared"}
          </p>
        </.section>
      </div>
    </.page>
    """
  end
end
