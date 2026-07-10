defmodule Flicker do
  @moduledoc """
  Flicker is an Ash-native searchable select / combobox / faceted-search
  library for Phoenix LiveView.

  It reads directly off Ash resources — no options plumbing — authorises via
  `actor:` and Ash policies, and derives facet behaviour from the Ash type
  system. Where Cinder is for tables, Flicker is for searching, filtering,
  and selecting records.

  The building blocks:

    * `Flicker.select/1` — the function component: a type-to-search,
      pick-one combobox over an Ash resource (or any `Flicker.Provider`).
    * `Flicker.Provider` — the behaviour every data source implements
      (`search/2`, `fetch/2`), and the internal invocation boundary
      (`run_search/3`, `run_fetch/3`) core code calls through.
    * `Flicker.Result` — the display struct providers return.
    * `Flicker.Query` — the search request struct passed to `search/2`.
    * `Flicker.Facet` — the (currently placeholder) faceted-search struct.
    * `Flicker.Providers.Static` — an in-memory reference provider, useful
      as a test double or for small fixed option lists.
    * `Flicker.Providers.AshResource` — the built-in provider Tier 1
      declarative component config compiles to.
    * `Flicker.Theme` — the class-per-part styling map (ADR-002).
    * `Flicker.Messages` — the overridable user-facing text behaviour
      (ADR-009).

  See the guides for how the component layer (built on top of this
  contract) is configured.
  """

  use Phoenix.Component

  alias Flicker.Components.Select, as: SelectComponent
  alias Flicker.Theme

  @default_limit 25
  @default_debounce 150

  @doc """
  Renders a type-to-search, pick-one combobox.

  ## Tier 1: declarative resource config

  The common case — no provider module of your own:

      <Flicker.select
        id="client-select"
        field={f[:client_id]}
        resource={MyApp.Client}
        actor={\@current_user}
        search={[:first_name, :last_name, :uci_number]}
        option_label={:full_name}
        option_sublabel={fn client -> "\#{client.uci_number} \#{client.city}" end}
        read_action={:search}
        limit={20}
      />

  `resource`, `search`, `option_label`, `option_sublabel`, `read_action`,
  `limit`, `sort`, and `filter` compile at mount to
  `{Flicker.Providers.AshResource, opts}` (ADR-001).

  ## Tier 2: a custom provider

  Pass `source` instead of `resource` — a module or `{module, opts}`
  implementing `Flicker.Provider`:

      <Flicker.select id="global-search" source={MyApp.Search.Global} actor={\@current_user} />

  ## Modes

  Passing `field` (a `Phoenix.HTML.FormField`, e.g. `f[:client_id]`) selects
  **form-field mode**: the component owns its hidden input and the
  `_unused_<field>` recovery marker (ADR-005); required-field errors don't
  fire until the field is engaged, and the value survives a LiveSocket
  reconnect.

  Omitting `field` and passing `on_select` (an atom) selects **controlled
  mode**: no form inputs are rendered; instead the host's `handle_info/2`
  receives `{on_select, %Flicker.Result{} | nil}` (`nil` on clear).

  Exactly one of `field` or `on_select` is required.

  ## Multi-select

  Passing `multiple` switches the value model to a list — the same
  component **is** the multi-select surface, there is no separate
  `Flicker.multi_select` (Spec 002). Selections render as removable chips;
  form-field mode emits `name[]` array hidden inputs; controlled mode's
  `on_select` carries the full selection list on every change. `fetch/2`
  resolves every preselected value in one call regardless of how many are
  set (ADR-003).

      <Flicker.select
        id="worker-select"
        field={f[:worker_ids]}
        multiple
        resource={MyApp.Worker}
        actor={\@current_user}
        search={[:name]}
        option_label={:name}
        max_selections={5}
      />

  ## Keyboard activation

  `activate_with_keyboard="mod+k"` focuses and opens this search from
  anywhere on the page — a global Cmd/Ctrl+K supersearch shortcut. See
  Spec 006 for the chord syntax and behaviour.
  """
  attr(:id, :string,
    required: true,
    doc: "DOM id for the component; also the assign namespace for its internal state."
  )

  attr(:resource, :atom,
    default: nil,
    doc: "Tier 1: the Ash resource to read. Requires `option_label`."
  )

  attr(:source, :any,
    default: nil,
    doc: "Tier 2: a `Flicker.Provider` module, or `{module, opts}`."
  )

  attr(:search, :list,
    default: [],
    doc: "Tier 1: attribute names `search/2`'s text match runs over."
  )

  attr(:option_label, :any,
    default: nil,
    doc: "Tier 1: an attribute name, or `fun(record) :: String.t()`."
  )

  attr(:option_sublabel, :any,
    default: nil,
    doc: "Tier 1: an attribute name, or `fun(record) :: String.t() | nil`."
  )

  attr(:read_action, :atom,
    default: nil,
    doc: "Tier 1: the read action to run. Defaults to `:read`."
  )

  attr(:sort, :any, default: nil, doc: "Tier 1: sort applied to search results.")

  attr(:filter, :any,
    default: nil,
    doc: "Tier 1: a base filter applied before the search-text match."
  )

  attr(:actor, :any,
    default: nil,
    doc: "The reading actor — passed through to the provider unmodified (ADR-004)."
  )

  attr(:tenant, :any,
    default: nil,
    doc: "The tenant — passed through to the provider unmodified."
  )

  attr(:field, Phoenix.HTML.FormField,
    default: nil,
    doc: "Selects form-field mode. See moduledoc."
  )

  attr(:required, :boolean,
    default: false,
    doc: "Form-field mode: marks the hidden input `required`."
  )

  attr(:on_select, :atom, default: nil, doc: "Selects controlled mode. See moduledoc.")

  attr(:multiple, :boolean,
    default: false,
    doc: "Switches the value model to a list — chips, `name[]` array inputs. See moduledoc."
  )

  attr(:max_selections, :integer,
    default: nil,
    doc: "Multi-select only: caps the number of selected values; further picking is disabled at the cap."
  )

  attr(:limit, :integer,
    default: nil,
    doc: "Max results shown. Defaults to `config :flicker, :default_limit` (25)."
  )

  attr(:min_chars, :integer, default: 0, doc: "Minimum typed characters before a search runs.")

  attr(:debounce, :integer,
    default: nil,
    doc: "Input debounce (ms). Defaults to `config :flicker, :default_debounce` (150)."
  )

  attr(:theme, :any,
    default: nil,
    doc: "A `Flicker.Theme` override — a full struct or a partial map. See `Flicker.Theme`."
  )

  attr(:messages, :atom,
    default: nil,
    doc: "A `Flicker.Messages` override module. See `Flicker.Messages`."
  )

  attr(:activate_with_keyboard, :string,
    default: nil,
    doc:
      "A chord string (e.g. `\"mod+k\"`) that focuses and opens this search from anywhere " <>
        "on the page. `mod` resolves to Cmd on macOS, Ctrl elsewhere. See Spec 006."
  )

  slot(:option, doc: "Custom option rendering, given the `Flicker.Result` as the slot argument.")

  @spec select(map()) :: Phoenix.LiveView.Rendered.t()
  def select(assigns) do
    provider = resolve_provider(assigns)
    validate_mode!(assigns)
    validate_chord!(assigns)

    assigns =
      assigns
      |> assign(:provider, provider)
      |> assign(
        :limit,
        assigns[:limit] || Application.get_env(:flicker, :default_limit, @default_limit)
      )
      |> assign(
        :debounce,
        assigns[:debounce] || Application.get_env(:flicker, :default_debounce, @default_debounce)
      )
      |> assign(:theme, Theme.resolve(assigns[:theme]))

    ~H"""
    <.live_component
      module={SelectComponent}
      id={@id}
      provider={@provider}
      field={@field}
      required={@required}
      on_select={@on_select}
      multiple={@multiple}
      max_selections={@max_selections}
      actor={@actor}
      tenant={@tenant}
      limit={@limit}
      min_chars={@min_chars}
      debounce={@debounce}
      theme={@theme}
      messages={@messages}
      activate_with_keyboard={@activate_with_keyboard}
      option={@option}
    />
    """
  end

  defp validate_mode!(%{field: nil, on_select: nil}) do
    raise ArgumentError, """
    Flicker.select/1 requires either `field` (form-field mode) or `on_select` (controlled mode).
    """
  end

  defp validate_mode!(_assigns), do: :ok

  # Fails loudly at the call site (Spec 006) rather than the hook silently
  # doing nothing in the browser for a malformed `activate_with_keyboard`.
  defp validate_chord!(%{activate_with_keyboard: chord}) when is_binary(chord), do: Flicker.Keyboard.validate!(chord)

  defp validate_chord!(_assigns), do: :ok

  defp resolve_provider(%{source: source}) when not is_nil(source), do: source

  defp resolve_provider(%{resource: resource} = assigns) when not is_nil(resource) do
    opts =
      [
        resource: resource,
        search: assigns[:search] || [],
        option_label: assigns[:option_label],
        option_sublabel: assigns[:option_sublabel],
        read_action: assigns[:read_action],
        sort: assigns[:sort],
        filter: assigns[:filter]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {Flicker.Providers.AshResource, opts}
  end

  defp resolve_provider(_assigns) do
    raise ArgumentError,
          "Flicker.select/1 requires either `resource` (Tier 1) or `source` (Tier 2)"
  end
end
