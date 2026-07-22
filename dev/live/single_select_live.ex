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

  defp sublabel(artist) do
    "formed #{artist.formed_on.year} · #{format_listeners(artist.monthly_listeners)} listeners"
  end

  defp format_listeners(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_listeners(n) when n >= 1_000, do: "#{div(n, 1_000)}k"
  defp format_listeners(n), do: to_string(n)

  defp tier_badge(%{tier: :legendary}), do: "bg-amber-100 text-amber-800"
  defp tier_badge(%{tier: :established}), do: "bg-indigo-100 text-indigo-800"
  defp tier_badge(_artist), do: "bg-gray-100 text-gray-600"

  defp controlled_message(:none), do: "— none yet, pick an artist —"
  defp controlled_message(nil), do: "{:controlled_selected, nil} (cleared)"

  defp controlled_message(result), do: "{:controlled_selected, %Flicker.Result{label: #{inspect(result.label)}, ...}}"

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
          <p class="mb-3 text-sm text-gray-500">
            <code>field={"{@form[:artist_id]}"}</code> makes the picker act like a
            native input: it renders a hidden input inside your
            <code>&lt;.form&gt;</code>, the value submits with the form's params,
            and required/validation integrate. Default option rendering:
            label + muted sublabel.
          </p>
          <.form for={@form} id="artist-form">
            <Flicker.select
              id="artist-form-select"
              field={@form[:artist_id]}
              resource={Artist}
              actor={@actor}
              search={[:name]}
              option_label={:name}
              option_sublabel={&sublabel/1}
            />
          </.form>
          <div class="mt-3 rounded-md bg-gray-50 px-3 py-2 font-mono text-xs text-gray-600">
            would submit: {inspect(@form.params, pretty: false)}
          </div>
        </.section>

        <.section label="Controlled mode">
          <p class="mb-3 text-sm text-gray-500">
            No <code>field</code>, no form inputs — <code>on_select</code> sends
            your LiveView a message with the picked result instead. This one
            also demos the <code>:option</code> slot: custom option markup with
            a right-aligned tier badge read from <code>result.meta.record</code>.
          </p>
          <Flicker.select
            id="artist-controlled-select"
            resource={Artist}
            actor={@actor}
            search={[:name]}
            option_label={:name}
            option_sublabel={&sublabel/1}
            on_select={:controlled_selected}
          >
            <:option :let={result}>
              <span class="flex w-full items-center justify-between gap-2">
                <span>
                  <span class="font-medium">{result.label}</span>
                  <span class="ml-2 text-xs text-gray-400">{result.sublabel}</span>
                </span>
                <span class={["rounded-full px-2 py-0.5 text-xs", tier_badge(result.meta.record)]}>
                  {result.meta.record.tier}
                </span>
              </span>
            </:option>
          </Flicker.select>
          <div class="mt-3 rounded-md bg-gray-50 px-3 py-2 font-mono text-xs text-gray-600">
            last message: {controlled_message(@selected_result)}
          </div>
        </.section>
      </div>
    </.page>
    """
  end
end
