defmodule Dev.Live.SingleSelect do
  @moduledoc """
  Playground page (Spec 005): `Flicker.select/1` in form-field mode and
  controlled mode, side by side, both reading `Dev.Music.Artist` — the
  seeded domain's policy-bearing resource, read here under a fixed public
  actor (`%{label: nil}`). A third, full-width section demos a richer
  `:option` slot — an avatar plus two lines of info per option.
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Dev.Music.Artist

  @impl true
  @doc "Seeds `Dev.Music` (private ETS, scoped to this LiveView process) and sets up both picker's state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:actor, %{label: nil})
      |> assign(:selected_result, :none)
      |> assign(:rich_result, :none)
      |> assign(:form, to_form(%{}, as: "artist"))

    {:ok, socket}
  end

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

  defp rich_message(:none), do: "— none yet, pick an artist —"
  defp rich_message(nil), do: "{:rich_selected, nil} (cleared)"

  defp rich_message(result), do: "{:rich_selected, %Flicker.Result{label: #{inspect(result.label)}, ...}}"

  @avatar_palette [
    "bg-rose-500 text-white",
    "bg-orange-500 text-white",
    "bg-amber-500 text-black",
    "bg-emerald-500 text-white",
    "bg-teal-500 text-white",
    "bg-sky-500 text-white",
    "bg-indigo-500 text-white",
    "bg-violet-500 text-white",
    "bg-fuchsia-500 text-white"
  ]

  defp avatar_initials(name) do
    name
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp avatar_color(name) do
    Enum.at(@avatar_palette, :erlang.phash2(name, length(@avatar_palette)))
  end

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

  def handle_info({:rich_selected, result}, socket) do
    {:noreply, assign(socket, :rich_result, result)}
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
  @doc "Renders both pickers."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assigns
      |> assign(:form_code, ~S"""
      <.form for={@form} id="artist-form">
        <Flicker.select
          id="artist-form-select"
          field={@form[:artist_id]}
          resource={MyApp.Music.Artist}
          search={[:name]}
          option_label={:name}
        />
      </.form>
      """)
      |> assign(:controlled_code, ~S'''
      <Flicker.select
        id="artist-controlled-select"
        resource={MyApp.Music.Artist}
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
      ''')
      |> assign(:rich_code, ~S'''
      <Flicker.select
        id="artist-rich-select"
        resource={MyApp.Music.Artist}
        search={[:name]}
        option_label={:name}
        on_select={:rich_selected}
      >
        <:option :let={result}>
          <span class="flex w-full items-center gap-3">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-semibold">
              {avatar_initials(result.label)}
            </span>
            <span class="flex flex-col">
              <span class="font-medium">{result.label}</span>
              <span class="text-xs text-gray-400">{sublabel(result.meta.record)}</span>
            </span>
            <span class="ml-auto rounded-full px-2 py-0.5 text-xs">
              {result.meta.record.tier}
            </span>
          </span>
        </:option>
      </Flicker.select>
      ''')

    ~H"""
    <.page title="Single select" current_path="/single-select" spec="docs/specs/spec-001-portable-single-select.md">
      <:description>
        Both pickers read <code>Dev.Music.Artist</code>, the policy-bearing
        resource, under a fixed public actor.
      </:description>

      <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
        <.section label="Form mode">
          <p class="mb-3 text-sm text-gray-500">
            <code>field={"{@form[:artist_id]}"}</code> makes the picker act like a
            native input: it renders a hidden input inside your
            <code>&lt;.form&gt;</code>, the value submits with the form's params,
            and required/validation integrate. Default option rendering:
            label + muted sublabel.
          </p>
          <.code_example id="single-form-code" code={@form_code}>
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
          </.code_example>
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
          <.code_example id="single-controlled-code" code={@controlled_code}>
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
          </.code_example>
          <div class="mt-3 rounded-md bg-gray-50 px-3 py-2 font-mono text-xs text-gray-600">
            last message: {controlled_message(@selected_result)}
          </div>
        </.section>
      </div>

      <.section label="Rich option slot (avatar + two lines)">
        <p class="mb-3 text-sm text-gray-500">
          The <code>:option</code> slot can render arbitrarily complex option UI —
          here each row shows an avatar (initials, deterministic colour) plus
          two stacked lines of info and a tier badge.
        </p>
        <.code_example id="single-rich-code" code={@rich_code}>
          <Flicker.select
            id="artist-rich-select"
            resource={Artist}
            actor={@actor}
            search={[:name]}
            option_label={:name}
            on_select={:rich_selected}
          >
            <:option :let={result}>
              <span class="flex w-full items-center gap-3">
                <span class={[
                  "flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-semibold",
                  avatar_color(result.label)
                ]}>
                  {avatar_initials(result.label)}
                </span>
                <span class="flex flex-col">
                  <span class="font-medium">{result.label}</span>
                  <span class="text-xs text-gray-400">{sublabel(result.meta.record)}</span>
                </span>
                <span class={[
                  "ml-auto rounded-full px-2 py-0.5 text-xs",
                  tier_badge(result.meta.record)
                ]}>
                  {result.meta.record.tier}
                </span>
              </span>
            </:option>
          </Flicker.select>
        </.code_example>
        <div class="mt-3 rounded-md bg-gray-50 px-3 py-2 font-mono text-xs text-gray-600">
          last message: {rich_message(@rich_result)}
        </div>
      </.section>
    </.page>
    """
  end
end
