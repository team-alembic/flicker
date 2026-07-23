defmodule Dev.Live.MultiSelect do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1 multiple` in form-field mode
  and controlled mode, stacked vertically, both reading `Dev.Music.Artist` —
  exercises Spec 002's chips, `max_selections` cap, and batch `fetch/2`
  label resolution (an edit-form picker mounts with three artists
  preselected). Each picker's own chip list shows the current selection, so
  neither demo needs a separate readout.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Music.Artist

  # Overlapping avatar stack (Spec 013): overrides only the selected-item
  # parts on top of the tailwind preset — negative spacing overlaps the
  # avatars, the "+N" token and each avatar carry a white ring, and the
  # library's remove control becomes a small × revealed on hover.
  @stack_theme %{
    selected_stack: "flex items-center -space-x-2",
    selected_item: "group relative",
    selected_overflow:
      "z-10 ml-3 inline-flex h-8 w-8 items-center justify-center rounded-full bg-gray-200 text-xs font-medium text-gray-600 ring-2 ring-white",
    chip_remove:
      "absolute -right-1 -top-1 hidden h-4 w-4 items-center justify-center rounded-full bg-gray-700 text-[10px] leading-none text-white group-hover:flex"
  }

  defp avatar_url(name), do: "https://api.dicebear.com/9.x/thumbs/svg?seed=" <> URI.encode(name)

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
      # `Dev.Music.Artist`'s read policy is `is_nil(label) or label ==
      # ^actor(:label)` — with no `actor:` at all (the bare `nil` default
      # every `Flicker.select` falls back to), Ash can't resolve
      # `actor(:label)` against a non-map actor and denies the whole read
      # outright (`Ash.Error.Forbidden`, not a per-row filter), which
      # `Provider.run_search/3` then surfaces as the generic error state on
      # both pickers below (BUG: "Something went wrong" on every search).
      # A public actor (`label: nil`, same shape `single_select_live.ex`
      # uses) is enough for the policy to resolve normally.
      |> assign(:actor, %{label: nil})
      |> assign(:stack_theme, @stack_theme)

    {:ok, socket}
  end

  @impl true
  @doc "Receives the controlled picker's selection list, and the form picker's field-value updates."
  @spec handle_info(
          {atom(), [Flicker.Result.t()]} | {module(), :selected, String.t(), [String.t()]},
          Phoenix.LiveView.Socket.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:controlled_selected, results}, socket) do
    {:noreply, assign(socket, :selected_results, results)}
  end

  # Form-field mode notifies the host with the field's new value (the full
  # id list) on every change so it can merge it into its own form params —
  # the same mechanic `single_select_live.ex` handles for its scalar field.
  # Without this clause every form-mode selection crashed this LiveView.
  def handle_info({Flicker.Components.Select, :selected, "artists[artist_ids]", value}, socket) do
    params = Map.put(socket.assigns.form.source || %{}, "artist_ids", value)
    {:noreply, assign(socket, :form, to_form(params, as: "artists"))}
  end

  def handle_info({:stack_selected, _results}, socket), do: {:noreply, socket}

  @impl true
  @doc "Renders both pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.page title="Multi-select" current_path="/multi-select" spec="docs/specs/spec-002-multi-select-chips.md">
      <:description>
        Both pickers read <code>Dev.Music.Artist</code>. The form-mode picker
        opens with three artists preselected — one <code>fetch/2</code> call
        resolves all three chips. The controlled picker caps at 4 selections.
      </:description>

      <div class="space-y-6">
        <.section label="Form mode (preselected)">
          <.form for={@form} id="artists-form">
            <Flicker.select
              id="artist-form-multiselect"
              field={@form[:artist_ids]}
              multiple
              resource={Artist}
              search={[:name]}
              option_label={:name}
              option_sublabel={fn artist -> "formed #{artist.formed_on.year}" end}
              actor={@actor}
            />
          </.form>
        </.section>

        <.section label="Controlled mode (max 4)">
          <Flicker.select
            id="artist-controlled-multiselect"
            resource={Artist}
            multiple
            max_selections={4}
            search={[:name]}
            option_label={:name}
            option_sublabel={fn artist -> "formed #{artist.formed_on.year}" end}
            on_select={:controlled_selected}
            actor={@actor}
          />
        </.section>

        <.section label="Avatar stack (:selected slot + max_visible)">
          <p class="mb-3 text-sm text-gray-500">
            A <code>:selected</code> slot renders each chosen record however you like —
            here as an avatar. With <code>max_visible={"{3}"}</code> the rest collapse
            into a "+N" token. Search and add a few artists to build the stack; hover an
            avatar to remove it.
          </p>
          <Flicker.select
            id="artist-stack-multiselect"
            resource={Artist}
            multiple
            max_visible={3}
            search={[:name]}
            option_label={:name}
            on_select={:stack_selected}
            actor={@actor}
            theme={@stack_theme}
          >
            <:option :let={result}>
              <span class="flex items-center gap-2">
                <img src={avatar_url(result.label)} alt="" class="h-6 w-6 rounded-full bg-gray-100" />
                <span class="font-medium">{result.label}</span>
              </span>
            </:option>
            <:selected :let={result}>
              <img
                src={avatar_url(result.label)}
                alt={result.label}
                title={result.label}
                class="h-8 w-8 rounded-full bg-gray-100 ring-2 ring-white"
              />
            </:selected>
          </Flicker.select>
        </.section>
      </div>
    </.page>
    """
  end
end
