defmodule Flicker.FacetEditor.Dial do
  @moduledoc """
  The numeric and duration editor ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)):
  a dual-thumb slider when the facet is bounded, paired numeric inputs either
  way.

  The slider is for feel and the inputs are for exactness; they are two views of
  one value. Both exist because either alone is worse — a slider can't express
  `10..` and a text box can't show you where the data sits.

  Which is the point of the **open bound**. A control that cannot say "over 100"
  is worse than the two text boxes it replaced, so an endpoint left blank
  serialises to `10..` or `..50` and is reachable from both views.

  Unbounded facets get the inputs alone: a slider needs endpoints, and inventing
  them would be a lie about the data.
  """

  @behaviour Flicker.FacetEditor

  use Phoenix.Component

  alias Flicker.Facet
  alias Flicker.Facet.{Format, Range}

  @impl true
  @doc """
  A range as a range literal, keeping an open end open; a scalar bare.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.serialise(%Flicker.Facet.Range{from: 10, to: 50}, facet)
      "10..50"

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.serialise(%Flicker.Facet.Range{from: 10, to: nil}, facet)
      "10.."

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.serialise(%Flicker.Facet.Range{from: nil, to: 50}, facet)
      "..50"

      iex> facet = Flicker.Facet.new(key: :length, type: :duration)
      ...> Flicker.FacetEditor.Dial.serialise(9000, facet)
      "9000s"
  """
  @spec serialise(term(), Facet.t()) :: String.t()
  def serialise(%Range{from: from, to: to}, facet) do
    "#{endpoint(from, facet)}..#{endpoint(to, facet)}"
  end

  def serialise(value, %Facet{type: :duration}) when is_integer(value), do: "#{value}s"
  def serialise(value, _facet), do: to_string(value)

  defp endpoint(nil, _facet), do: ""
  defp endpoint(value, %Facet{scalar: :duration}), do: "#{value}s"
  defp endpoint(value, _facet), do: to_string(value)

  @impl true
  @doc """
  Delegates to the facet's own casting, so a dial can never produce a token the
  parser rejects.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> {:ok, range} = Flicker.FacetEditor.Dial.parse("10..50", facet)
      ...> {range.from, range.to}
      {10, 50}

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.parse("nonsense", facet)
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
  At least one endpoint is required. Both open would mean "don't filter", which
  is what removing the facet is for.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.complete?(%Flicker.Facet.Range{from: 10}, facet)
      true

      iex> facet = Flicker.Facet.new(key: :price, type: :number_range)
      ...> Flicker.FacetEditor.Dial.complete?(%Flicker.Facet.Range{}, facet)
      false

      iex> facet = Flicker.Facet.new(key: :n, type: :integer)
      ...> Flicker.FacetEditor.Dial.complete?(5, facet)
      true
  """
  @spec complete?(term(), Facet.t()) :: boolean()
  def complete?(%Range{from: nil, to: nil}, _facet), do: false
  def complete?(%Range{}, _facet), do: true
  def complete?(value, _facet) when is_number(value), do: true
  def complete?(_value, _facet), do: false

  @doc """
  A thumb's position as a percentage of the facet's bounds, clamped to `0..100`.

  Returns `nil` for an open endpoint or an unbounded facet — there is no
  meaningful position for either, and guessing one would misrepresent the value.

  ## Examples

      iex> Flicker.FacetEditor.Dial.thumb_percent(50, %{min: 0, max: 100})
      50.0

      iex> Flicker.FacetEditor.Dial.thumb_percent(150, %{min: 0, max: 100})
      100.0

      iex> Flicker.FacetEditor.Dial.thumb_percent(nil, %{min: 0, max: 100})
      nil

      iex> Flicker.FacetEditor.Dial.thumb_percent(50, nil)
      nil
  """
  @spec thumb_percent(number() | nil, map() | nil) :: float() | nil
  def thumb_percent(nil, _bounds), do: nil
  def thumb_percent(_value, nil), do: nil

  def thumb_percent(value, bounds) do
    min = Map.get(bounds, :min)
    max = Map.get(bounds, :max)

    if is_number(min) and is_number(max) and max > min do
      ((value - min) / (max - min) * 100) |> max(0.0) |> min(100.0)
    end
  end

  @doc """
  Clamps a would-be endpoint so the thumbs can't cross — the lower may equal the
  upper, but never pass it.

  ## Examples

      iex> Flicker.FacetEditor.Dial.clamp_endpoint(:from, 80, %Flicker.Facet.Range{from: 10, to: 50})
      50

      iex> Flicker.FacetEditor.Dial.clamp_endpoint(:to, 5, %Flicker.Facet.Range{from: 10, to: 50})
      10

      iex> Flicker.FacetEditor.Dial.clamp_endpoint(:from, 20, %Flicker.Facet.Range{from: 10, to: 50})
      20

      iex> Flicker.FacetEditor.Dial.clamp_endpoint(:from, 80, %Flicker.Facet.Range{to: nil})
      80
  """
  @spec clamp_endpoint(:from | :to, number(), Range.t()) :: number()
  def clamp_endpoint(:from, value, %Range{to: to}) when is_number(to), do: min(value, to)
  def clamp_endpoint(:to, value, %Range{from: from}) when is_number(from), do: max(value, from)
  def clamp_endpoint(_side, value, _range), do: value

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class={@theme.facet_editor_body}>
      <%!-- Bounded facets get the slider; unbounded ones get the inputs alone,
      since a slider without endpoints would be inventing them. --%>
      <div :if={@bounds} class={@theme.dial}>
        <div class={@theme.dial_track} aria-hidden="true">
          <div
            class={@theme.dial_fill}
            style={"left:#{@from_percent || 0}%;right:#{100 - (@to_percent || 100)}%"}
          >
          </div>
        </div>
        <span
          :for={{side, percent, value} <- [{:from, @from_percent, @value_from}, {:to, @to_percent, @value_to}]}
          role="slider"
          tabindex="0"
          class={@theme.dial_thumb}
          style={"left:#{percent || 0}%"}
          aria-label={@labels[side]}
          aria-valuemin={@bounds[:min]}
          aria-valuemax={@bounds[:max]}
          aria-valuenow={value}
          aria-valuetext={value && Format.value_label(@facet, value)}
          data-flicker-dial-thumb={to_string(side)}
        >
        </span>
      </div>
      <div class={@theme.dial_value_label}>{@footer}</div>
      <%!-- Blank means open, which is how "over 100" stays expressible. --%>
      <form phx-change="facet_editor_input" phx-target={@target}>
        <input
          type="text"
          inputmode="decimal"
          name="from"
          value={@value_from}
          class={@theme.dial_input}
          aria-label={@labels.from}
          disabled={@disabled}
        />
        <input
          type="text"
          inputmode="decimal"
          name="to"
          value={@value_to}
          class={@theme.dial_input}
          aria-label={@labels.to}
          disabled={@disabled}
        />
      </form>
    </div>
    """
  end
end
