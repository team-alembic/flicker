defmodule Flicker.FacetEditor do
  @moduledoc """
  The contract every rich facet editor implements
  ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)).

  Per [ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)
  an editor is a modal sub-context whose **only output is token text**. It holds
  no committed state, it never queries on its own, and it commits exactly once —
  when its value is complete. Everything it can express, a user can type;
  everything a user can type, it can be opened on. That symmetry is what keeps
  `Flicker.Query.input` the single source of truth.

  ## The callbacks

    * `c:serialise/2` — the value's canonical token text, *without* the
      `key:` prefix or a trailing space (the component adds both). Locale-
      invariant, per [ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md).
    * `c:parse/2` — the inverse: an editor's own value from a token's value
      text, for reopening a committed facet.
    * `c:complete?/2` — whether this value may commit yet. A half-made range
      is a draft, and no route (`Enter`, click, Done) may commit one.
    * `c:render/1` — the editor's markup.
    * `c:draft_label/3` — optional one-line summary of an incomplete value, for
      the footer ("Jun 18, 2026 → pick an end date").
    * `c:modal?/0` — optional; `false` for an editor whose value is complete in
      one interaction and so needs no pop-out. The switch is the only one.

  `serialise/2` and `parse/2` are a round-trip pair, and the property that pair
  must satisfy is the load-bearing test of this spec:

      serialise(parse(serialise(value))) == serialise(value)

  Note that this is idempotence of `serialise/2`, not structural identity of the
  value — deliberately. A preset serialises to its id (`last-30-days`) and parses
  back **resolved** (a `%Range{}` with real endpoints *and* the preset id), which
  is the whole point of presets staying relative. The two forms mean the same
  thing and serialise identically; they are not the same struct. For every
  non-preset value the property does collapse to plain identity.

  The second half matters just as much: the text an editor emits must re-parse to
  a real filter through `Flicker.Query.parse/2`. An editor that drifts from the
  grammar fails that, which is what makes token text a safe sole output.
  """

  alias Flicker.Facet

  @typedoc "An editor's own working value. Its shape is the editor's business."
  @type value :: term()

  @doc "The editor's markup."
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc "Canonical token text for `value` — no `key:` prefix, no trailing space."
  @callback serialise(value(), Facet.t()) :: String.t()

  @doc "An editor value from a token's value text, for reopening a committed facet."
  @callback parse(String.t(), Facet.t()) :: {:ok, value()} | :error

  @doc "Whether `value` is complete enough to commit."
  @callback complete?(value(), Facet.t()) :: boolean()

  @doc "A one-line summary of an incomplete value, or `nil`."
  @callback draft_label(value(), Facet.t(), keyword()) :: String.t() | nil

  @doc "Whether this editor needs a modal pop-out. Defaults to `true`."
  @callback modal?() :: boolean()

  @optional_callbacks draft_label: 3, modal?: 0

  @doc """
  The editor for `facet` — its own `:editor` when set, otherwise the default for
  its type, or `nil` for a type that has none (a plain `:string` facet, or an
  unbounded numeric one, where typing straight through beats any control).

  ## Examples

      iex> Flicker.FacetEditor.for_facet(Flicker.Facet.new(key: :created, type: :date_range))
      Flicker.FacetEditor.Calendar

      iex> Flicker.FacetEditor.for_facet(Flicker.Facet.new(key: :verified?, type: :boolean))
      Flicker.FacetEditor.Switch

      iex> Flicker.FacetEditor.for_facet(Flicker.Facet.new(key: :status, type: :enum, values: [:a]))
      Flicker.FacetEditor.Set

      iex> Flicker.FacetEditor.for_facet(Flicker.Facet.new(key: :name, type: :string))
      nil

      iex> Flicker.FacetEditor.for_facet(Flicker.Facet.new(key: :n, type: :integer))
      nil

      iex> Flicker.FacetEditor.for_facet(
      ...>   Flicker.Facet.new(key: :n, type: :integer, bounds: %{min: 0, max: 9})
      ...> )
      Flicker.FacetEditor.Dial
  """
  @spec for_facet(Facet.t()) :: module() | nil
  def for_facet(%Facet{editor: editor}) when not is_nil(editor), do: editor

  def for_facet(%Facet{type: type}) when type in [:date, :date_range, :datetime, :datetime_range],
    do: Flicker.FacetEditor.Calendar

  def for_facet(%Facet{type: :number_range}), do: Flicker.FacetEditor.Dial
  def for_facet(%Facet{type: :duration}), do: Flicker.FacetEditor.Dial
  def for_facet(%Facet{type: :boolean}), do: Flicker.FacetEditor.Switch

  # An unbounded numeric facet gets no dial: a slider needs endpoints, and
  # inventing them would be worse than the text field the user already has.
  def for_facet(%Facet{type: type, bounds: bounds}) when type in [:integer, :float] and is_map(bounds),
    do: Flicker.FacetEditor.Dial

  def for_facet(%Facet{type: :enum}), do: Flicker.FacetEditor.Set

  def for_facet(%Facet{related: related}) when not is_nil(related), do: Flicker.FacetEditor.Set

  def for_facet(%Facet{}), do: nil

  @doc """
  Whether `facet` has a rich editor at all.

  ## Examples

      iex> Flicker.FacetEditor.editable?(Flicker.Facet.new(key: :created, type: :date_range))
      true

      iex> Flicker.FacetEditor.editable?(Flicker.Facet.new(key: :name, type: :string))
      false
  """
  @spec editable?(Facet.t()) :: boolean()
  def editable?(facet), do: for_facet(facet) != nil

  @doc """
  Whether opening `facet`'s editor should take over the surface with a pop-out.

  `false` for an editor whose value is complete in one interaction — the switch.
  Atomic commit is mandatory either way; a pop-out is only what *multi-step*
  values need.

  ## Examples

      iex> Flicker.FacetEditor.modal?(Flicker.Facet.new(key: :created, type: :date_range))
      true

      iex> Flicker.FacetEditor.modal?(Flicker.Facet.new(key: :verified?, type: :boolean))
      false

      iex> Flicker.FacetEditor.modal?(Flicker.Facet.new(key: :name, type: :string))
      false
  """
  @spec modal?(Facet.t()) :: boolean()
  def modal?(facet) do
    case for_facet(facet) do
      nil -> false
      editor -> not function_exported?(editor, :modal?, 0) or editor.modal?()
    end
  end

  @doc """
  The full token an editor's value commits as — `key:value ` — or `nil` when the
  value isn't complete.

  The trailing space is deliberate: it matches what every other suggestion
  inserts, so `Flicker.FacetSuggest.replace_current_token/3` leaves the caret
  ready for the next token.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :verified?, type: :boolean)
      ...> Flicker.FacetEditor.to_token(Flicker.FacetEditor.Switch, true, facet)
      "verified?:true "

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...>
      ...> Flicker.FacetEditor.to_token(
      ...>   Flicker.FacetEditor.Calendar,
      ...>   %Flicker.Facet.Range{from: ~D[2026-07-01]},
      ...>   facet
      ...> )
      "created:2026-07-01.. "

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...>
      ...> Flicker.FacetEditor.to_token(
      ...>   Flicker.FacetEditor.Calendar,
      ...>   %Flicker.Facet.Range{},
      ...>   facet
      ...> )
      nil
  """
  @spec to_token(module(), value(), Facet.t()) :: String.t() | nil
  def to_token(editor, value, facet) do
    if editor.complete?(value, facet) do
      "#{facet.key}:#{editor.serialise(value, facet)} "
    end
  end
end
