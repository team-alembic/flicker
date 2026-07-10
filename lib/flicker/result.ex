defmodule Flicker.Result do
  @moduledoc """
  A single searchable/selectable option, as returned by a `Flicker.Provider`.

  This is the one display shape every provider — the built-in
  `Flicker.Providers.AshResource`, `Flicker.Providers.Static`, or a
  hand-written provider wrapping an external API — normalises its data into.
  Core rendering code only ever sees `Flicker.Result` structs, never raw
  provider data.

  ## Fields

    * `:value` — the identifier stored when this option is selected (an Ash
      primary key, an external id, or any term meaningful to the provider).
      Compared as-is by the provider on `fetch/2`; core code treats it as an
      opaque term.
    * `:label` — the primary, user-facing text for the option.
    * `:sublabel` — optional secondary text (e.g. a disambiguating detail).
      `nil` when there is none.
    * `:meta` — a free-form map for provider- or theme-specific extras (e.g.
      data a custom `render_option/2` implementation wants). Defaults to
      `%{}`. `Flicker.palette/1`'s navigate-on-select convention reads
      `meta.href` — when set to a path, selecting the result issues a
      `push_navigate/2` to it ([Spec 008](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-008-command-palette.md)).
    * `:group` — optional group label (e.g. `"Artists"`, `"Albums"`). When
      any result in a list carries one, the core listbox renders a
      contiguous, non-interactive group-header row before the first result
      of each new group — providers own the ordering, the core never
      re-sorts by group. `nil` (the default) opts a provider out entirely:
      a groupless result list renders exactly as it always has (Spec 008).
  """

  @typedoc "A display-ready search/select option."
  @type t :: %__MODULE__{
          value: term(),
          label: String.t(),
          sublabel: String.t() | nil,
          meta: map(),
          group: String.t() | nil
        }

  @enforce_keys [:value, :label]
  defstruct value: nil, label: nil, sublabel: nil, meta: %{}, group: nil
end
