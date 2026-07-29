defmodule Flicker.FacetEditor.Set do
  @moduledoc """
  The editor for a facet whose values come from a set — an `:enum`'s closed
  picklist, or a relationship's related records
  ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)).

  It is a nested `Flicker.select`
  ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)):
  the two cases differ only in the provider behind them, which
  `Flicker.Facet.value_source/1` supplies. That means Spec 002's chips, Spec
  013's `:selected` slot, Spec 017's value colours, Spec 010's windowing and
  every future `Flicker.select` improvement arrive here for free rather than
  being reimplemented.

  The nested select runs **controlled, with no facets of its own** — facet
  editing never recurses. An editor may contain a select and a select may open
  an editor, but an editor's select is a leaf, which is what keeps focus depth
  bounded.

  Multi mode commits the whole selection as one `:in` token rather than
  per-toggle, so widening a selection is one dispatch, not five.
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
      <%!-- Controlled, and deliberately given no `facets` of its own: facet
      editing never recurses (ADR-011's leaf rule). --%>
      <Flicker.select
        id={"#{@id}-set"}
        source={@source}
        multiple={@facet.multiple?}
        actor={@actor}
        tenant={@tenant}
        on_select={@on_select}
        theme={@select_theme}
        messages={@messages}
      />
    </div>
    """
  end
end
