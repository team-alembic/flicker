defmodule Flicker.FacetEditor.Calendar do
  @moduledoc """
  The date and date-range editor ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)):
  a presets rail beside one or two month grids, with a footer carrying the draft
  state.

  Two details carry most of the value. Each preset row shows **the range it
  resolves to** ("Last 30 days · Jun 29 – Jul 28"), so presets are trustworthy
  rather than mysterious. And a range takes two clicks, with the footer reading
  `Jun 18, 2026 → pick an end date` in between — an incomplete value that looks
  incomplete, instead of an inert control.

  Choosing a preset commits its **id**, not the dates it resolved to, so a saved
  or shared query stays relative
  ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)).

  Month names, weekday initials and the locale's own first day of week come from
  `localize` where present
  ([ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md)),
  falling back to English and Monday.
  """

  @behaviour Flicker.FacetEditor

  use Phoenix.Component

  alias Flicker.Facet
  alias Flicker.Facet.{Format, Preset, Range}

  @weekday_initials ~w(M T W T F S S)

  @impl true
  @doc """
  A preset commits as its token; an explicit range as a range literal; a single
  date as an ISO date.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...>
      ...> Flicker.FacetEditor.Calendar.serialise(
      ...>   %Flicker.Facet.Range{preset: :last_30_days},
      ...>   facet
      ...> )
      "last-30-days"

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> range = %Flicker.Facet.Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}
      ...> Flicker.FacetEditor.Calendar.serialise(range, facet)
      "2026-06-01..2026-06-30"

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> Flicker.FacetEditor.Calendar.serialise(%Flicker.Facet.Range{from: ~D[2026-06-01]}, facet)
      "2026-06-01.."

      iex> facet = Flicker.Facet.new(key: :created, type: :date)
      ...> Flicker.FacetEditor.Calendar.serialise(~D[2026-06-01], facet)
      "2026-06-01"
  """
  @spec serialise(term(), Facet.t()) :: String.t()
  def serialise(%Range{preset: preset}, facet) when not is_nil(preset) do
    case Preset.find_by_id(preset, facet.presets || Preset.builtin()) do
      nil -> ""
      found -> found.token
    end
  end

  def serialise(%Range{from: from, to: to}, _facet) do
    "#{endpoint(from)}..#{endpoint(to)}"
  end

  def serialise(%Date{} = date, _facet), do: Date.to_iso8601(date)
  def serialise(%DateTime{} = datetime, _facet), do: DateTime.to_iso8601(datetime)

  defp endpoint(nil), do: ""
  defp endpoint(%Date{} = date), do: Date.to_iso8601(date)
  defp endpoint(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  @impl true
  @doc """
  Delegates to the facet's own casting, so the editor can never accept a token
  the parser would reject.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> {:ok, range} = Flicker.FacetEditor.Calendar.parse("last-30-days", facet)
      ...> range.preset
      :last_30_days

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> Flicker.FacetEditor.Calendar.parse("nonsense", facet)
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
  A preset is complete. An explicit range needs at least one endpoint — a lone
  draft start is not committable, which is exactly what the footer's
  "pick an end date" is telling the user.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> Flicker.FacetEditor.Calendar.complete?(%Flicker.Facet.Range{preset: :all_time}, facet)
      true

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> range = %Flicker.Facet.Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}
      ...> Flicker.FacetEditor.Calendar.complete?(range, facet)
      true

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> Flicker.FacetEditor.Calendar.complete?(%Flicker.Facet.Range{}, facet)
      false
  """
  @spec complete?(term(), Facet.t()) :: boolean()
  def complete?(%Range{preset: preset}, _facet) when not is_nil(preset), do: true
  def complete?(%Range{from: nil, to: nil}, _facet), do: false
  def complete?(%Range{}, _facet), do: true
  def complete?(%Date{}, _facet), do: true
  def complete?(%DateTime{}, _facet), do: true
  def complete?(_value, _facet), do: false

  @impl true
  @doc """
  The footer line: a draft start with no end says so in words, rather than
  leaving the control looking inert.
  """
  @spec draft_label(term(), Facet.t(), keyword()) :: String.t() | nil
  def draft_label(%Range{from: from, to: nil}, facet, opts) when not is_nil(from) do
    "#{Format.value_label(facet, from)} → #{Keyword.get(opts, :prompt, "pick an end date")}"
  end

  def draft_label(_value, _facet, _opts), do: nil

  @doc """
  The days to render for `month`, as full weeks starting on `first_day_of_week`.

  Leading and trailing days from adjacent months are included as `nil` so the
  grid stays rectangular without rendering neighbouring dates as pickable.

  ## Examples

      iex> Flicker.FacetEditor.Calendar.month_grid(~D[2026-07-01], 1) |> length() |> rem(7)
      0

      iex> grid = Flicker.FacetEditor.Calendar.month_grid(~D[2026-07-01], 1)
      ...> Enum.take(grid, 3)
      [nil, nil, ~D[2026-07-01]]
  """
  @spec month_grid(Date.t(), 1..7) :: [Date.t() | nil]
  def month_grid(month, first_day_of_week) do
    first = Date.beginning_of_month(month)
    last = Date.end_of_month(month)
    leading = Integer.mod(Date.day_of_week(first) - first_day_of_week, 7)
    days = Enum.map(0..(last.day - 1), &Date.add(first, &1))
    padded = List.duplicate(nil, leading) ++ days
    trailing = Integer.mod(-length(padded), 7)

    padded ++ List.duplicate(nil, trailing)
  end

  @doc """
  Weekday initials starting on `first_day_of_week`.

  ## Examples

      iex> Flicker.FacetEditor.Calendar.weekday_initials(1)
      ["M", "T", "W", "T", "F", "S", "S"]

      iex> Flicker.FacetEditor.Calendar.weekday_initials(7) |> hd()
      "S"
  """
  @spec weekday_initials(1..7) :: [String.t()]
  def weekday_initials(first_day_of_week) do
    rotation = first_day_of_week - 1

    Enum.map(0..6, fn index -> Enum.at(@weekday_initials, Integer.mod(index + rotation, 7)) end)
  end

  @doc """
  Whether `date` falls inside the range being built, for the hover band.

  Takes the hovered day so a half-made range still previews — the interaction
  that makes a two-click range feel like one gesture.

  ## Examples

      iex> Flicker.FacetEditor.Calendar.in_band?(~D[2026-07-05], ~D[2026-07-01], ~D[2026-07-10])
      true

      iex> Flicker.FacetEditor.Calendar.in_band?(~D[2026-07-20], ~D[2026-07-01], ~D[2026-07-10])
      false

      iex> Flicker.FacetEditor.Calendar.in_band?(~D[2026-07-05], ~D[2026-07-01], nil)
      false
  """
  @spec in_band?(Date.t(), Date.t() | nil, Date.t() | nil) :: boolean()
  def in_band?(_date, nil, _other), do: false
  def in_band?(_date, _start, nil), do: false

  def in_band?(date, start, other) do
    {low, high} = if Date.after?(start, other), do: {other, start}, else: {start, other}

    Date.compare(date, low) != :lt and Date.compare(date, high) != :gt
  end

  @doc """
  The months to render, tagged `:first`/`:last` so only the outer grids carry
  their paging control.

  Two for a range type, one otherwise. A single month is both first and last.

  ## Examples

      iex> Flicker.FacetEditor.Calendar.month_grids(~D[2026-07-01], 1)
      [{~D[2026-07-01], :only}]

      iex> Flicker.FacetEditor.Calendar.month_grids(~D[2026-07-01], 2)
      [{~D[2026-07-01], :first}, {~D[2026-08-01], :last}]
  """
  @spec month_grids(Date.t(), pos_integer()) :: [{Date.t(), :only | :first | :last}]
  def month_grids(month, 1), do: [{Date.beginning_of_month(month), :only}]

  def month_grids(month, _count) do
    first = Date.beginning_of_month(month)
    second = first |> Date.end_of_month() |> Date.add(1)

    [{first, :first}, {second, :last}]
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class={@theme.facet_editor_body}>
      <div class={@theme.preset_rail}>
        <p :if={@suggested != []} class={@theme.preset_group_label}>{@labels.suggested}</p>
        <button
          :for={preset <- @presets}
          type="button"
          class={[@theme.preset_row, @value_preset == preset.id && @theme.preset_row_selected]}
          disabled={@disabled}
          phx-click="facet_editor_commit"
          phx-value-insert={"#{@facet.key}:#{preset.token} "}
          phx-target={@target}
        >
          <span>{preset.label}</span>
          <%!-- The resolved range, shown so a preset is trustworthy rather
          than mysterious. --%>
          <span class={@theme.preset_row_range}>{resolved_label(preset, @facet, @today, @first_day_of_week)}</span>
        </button>
      </div>
      <%!-- Two months for a range, one for a single date: picking a span that
      crosses a month boundary in one gesture is most of why a range picker
      beats two date fields. --%>
      <div :for={{month, position} <- @month_grids} class={@theme.calendar}>
        <div class={@theme.calendar_nav}>
          <button
            :if={position == :first}
            type="button"
            class={@theme.calendar_nav_button}
            aria-label={@labels.previous_month}
            disabled={@disabled}
            phx-click="facet_editor_month"
            phx-value-month={Date.to_iso8601(Date.add(Date.beginning_of_month(@month), -1))}
            phx-target={@target}
          >
            ‹
          </button>
          <span class={@theme.calendar_month_label}>{Format.value_label(@facet, month)}</span>
          <button
            :if={position == :last}
            type="button"
            class={@theme.calendar_nav_button}
            aria-label={@labels.next_month}
            disabled={@disabled}
            phx-click="facet_editor_month"
            phx-value-month={Date.to_iso8601(Date.add(Date.end_of_month(@month), 1))}
            phx-target={@target}
          >
            ›
          </button>
        </div>
        <div class={@theme.calendar_grid} role="grid">
          <span :for={initial <- weekday_initials(@first_day_of_week)} class={@theme.calendar_weekday}>
            {initial}
          </span>
          <%= for day <- month_grid(month, @first_day_of_week) do %>
            <%= if day do %>
              <button
                type="button"
                role="gridcell"
                aria-selected={to_string(day in [@draft_start, @value_from, @value_to])}
                class={[
                  @theme.calendar_day,
                  day == @today && @theme.calendar_day_today,
                  day in [@value_from, @value_to, @draft_start] && @theme.calendar_day_selected,
                  in_band?(day, @draft_start || @value_from, @hover || @value_to) && @theme.calendar_day_in_range
                ]}
                disabled={@disabled}
                phx-click="facet_editor_pick"
                phx-value-date={Date.to_iso8601(day)}
                phx-target={@target}
              >
                {day.day}
              </button>
            <% else %>
              <span class={@theme.calendar_day_disabled} aria-hidden="true"></span>
            <% end %>
          <% end %>
        </div>
        <div :if={position == :last} class={@theme.facet_editor_footer}>
          <span>{@footer}</span>
        </div>
      </div>
    </div>
    """
  end

  defp resolved_label(preset, facet, today, first_day_of_week) do
    resolved = Preset.resolve(preset, today, first_day_of_week)

    if Range.unbounded?(resolved) do
      ""
    else
      Format.range_label(%{facet | presets: []}, %{resolved | preset: nil})
    end
  end
end
