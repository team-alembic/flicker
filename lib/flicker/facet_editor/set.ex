defmodule Flicker.FacetEditor.Set do
  @moduledoc """
  The editor for a facet whose values come from a set — an `:enum`'s closed
  picklist, or a relationship's related records
  ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)).

  Both cases are driven by one thing — `Flicker.Facet.value_source/1` — so the
  enum and relationship editors are the same code with a different provider
  behind them, which was
  [ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)'s
  actual goal.

  ## Why this isn't literally a nested `Flicker.select`

  ADR-011 said the set editor *is* a nested `Flicker.select`. Implementation
  showed that doesn't work: `Flicker.select`'s controlled mode sends
  `{on_select, result}` with `send(self(), ...)`, and `self()` inside a
  `Phoenix.LiveComponent` is the **host LiveView**, not the enclosing component.
  A nested select could therefore never hand its selection back to the editor
  that contains it without every host adding a `handle_info` clause to forward
  it — exactly the boilerplate a library shouldn't impose.

  So this renders the value list itself, against the same `value_source/1`, with
  its events targeted at the component that owns the editor. The unification
  ADR-011 wanted is intact; the specific mechanism isn't. What is genuinely lost
  is inheriting `Flicker.select`'s own listbox behaviour for free — windowing
  over a very large related set is the notable gap, and is why `:count_limit`
  and a search box matter here.

  Multi mode commits the whole selection as one `:in` token rather than
  per-toggle, so widening a selection is one dispatch, not five. Facet editing
  never recurses: this list has no facets of its own.
  """

  @behaviour Flicker.FacetEditor

  use Phoenix.Component

  alias Flicker.Facet

  @impl true
  @doc """
  A single value bare, a multi selection comma-joined — exactly the list literal
  Spec 018's grammar accepts.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a, :b], multiple?: true)
      ...> Flicker.FacetEditor.Set.serialise([:a, :b], facet)
      "a,b"

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a])
      ...> Flicker.FacetEditor.Set.serialise(:a, facet)
      "a"

      iex> facet = Flicker.Facet.new(key: :worker, type: :string)
      ...> Flicker.FacetEditor.Set.serialise("Casey Nguyen", facet)
      ~s("Casey Nguyen")
  """
  @spec serialise(term(), Facet.t()) :: String.t()
  def serialise(values, facet) when is_list(values) do
    Enum.map_join(values, ",", &serialise(&1, facet))
  end

  def serialise(value, _facet), do: quote_if_needed(to_string(value))

  defp quote_if_needed(value) do
    if String.contains?(value, [" ", "\"", ","]) do
      ~s("#{String.replace(value, "\"", "\\\"")}")
    else
      value
    end
  end

  @impl true
  @doc """
  Splits a list literal for a `multiple?` facet, and casts through the facet so
  an enum comes back as atoms rather than strings.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a, :b], multiple?: true)
      ...> Flicker.FacetEditor.Set.parse("a,b", facet)
      {:ok, [:a, :b]}

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a])
      ...> Flicker.FacetEditor.Set.parse("a", facet)
      {:ok, :a}

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a])
      ...> Flicker.FacetEditor.Set.parse("nope", facet)
      :error
  """
  @spec parse(String.t(), Facet.t()) :: {:ok, term()} | :error
  def parse(text, facet) do
    case Facet.cast_value(facet, text, facet.default_op) do
      {:ok, _op, value} -> {:ok, value}
      {:error, _reason} -> :error
    end
  end

  @impl true
  @doc """
  A non-empty selection is complete; nothing selected is not.

  ## Examples

      iex> Flicker.FacetEditor.Set.complete?([:a], %Flicker.Facet{key: :s})
      true

      iex> Flicker.FacetEditor.Set.complete?([], %Flicker.Facet{key: :s})
      false

      iex> Flicker.FacetEditor.Set.complete?(nil, %Flicker.Facet{key: :s})
      false
  """
  @spec complete?(term(), Facet.t()) :: boolean()
  def complete?(nil, _facet), do: false
  def complete?([], _facet), do: false
  def complete?(_value, _facet), do: true

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class={@theme.facet_editor_body}>
      <div role="listbox" aria-multiselectable={to_string(@facet.multiple?)} aria-label={@labels.values}>
        <button
          :for={candidate <- @candidates}
          type="button"
          role="option"
          aria-selected={to_string(candidate.value in @selected)}
          class={[@theme.option, candidate.value in @selected && @theme.option_active]}
          disabled={@disabled}
          phx-click={if @facet.multiple?, do: "facet_editor_toggle", else: "facet_editor_commit"}
          phx-value-value={to_string(candidate.value)}
          phx-value-insert={
            unless @facet.multiple? do
              "#{@facet.key}:#{serialise(candidate.value, @facet)} "
            end
          }
          phx-target={@target}
        >
          <span
            :if={@facet.value_colors && @facet.value_colors[candidate.value]}
            aria-hidden="true"
            style={"background-color:#{@facet.value_colors[candidate.value]}"}
            class="mr-1 inline-block h-2 w-2 shrink-0 rounded-full"
          >
          </span>
          <span>{candidate.label}</span>
          <span :if={@counts[candidate.value]} class={@theme.facet_count}>{@counts[candidate.value]}</span>
        </button>
      </div>
      <%!-- Multi mode commits once, for the whole selection — not per toggle. --%>
      <div :if={@facet.multiple?} class={@theme.facet_editor_footer}>
        <span>{@footer}</span>
        <button
          type="button"
          disabled={@disabled or @selected == []}
          phx-click="facet_editor_commit"
          phx-value-insert={@done_token}
          phx-target={@target}
        >
          {@labels.done}
        </button>
      </div>
    </div>
    """
  end
end
