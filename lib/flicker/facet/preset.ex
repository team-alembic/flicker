defmodule Flicker.Facet.Preset do
  @moduledoc """
  A semantic date preset — `last-30-days`, `this-quarter`, `all-time`
  ([Spec 018](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-018-rich-facet-types.md)).

  A preset is the *question* a user is asking ("the last 30 days"), not the
  answer ("Jun 29 to Jul 28"). That distinction is load-bearing: presets
  serialise back to their `:token`, so a query saved today still means "the
  last 30 days" when reopened next week, rather than freezing to this week's
  dates ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)).

  ## Fields

    * `:id` — the canonical atom (`:last_30_days`), carried on
      `Flicker.Facet.Range`'s `:preset`.
    * `:token` — the typed/serialised form (`"last-30-days"`).
    * `:label` — the fallback display string. With `localize` present,
      `Flicker.Facet.Format` prefers CLDR's own wording
      ([ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md)).
    * `:resolve` — `fun(reference_date, first_day_of_week) :: {from, to}`.

  ## Resolution is contextual, and takes its context as arguments

  `:resolve` never calls `Date.utc_today/0` and never reads a locale: both
  the reference date and the week's first day arrive as arguments. That keeps
  every preset a pure function — the whole table is testable at a fixed date
  — and it is what lets `this-week` mean different days in `en-US` (Sunday
  start) and `en-AU` (Monday start) without the preset knowing anything about
  locales.

  `first_day_of_week` is `1` for Monday through `7` for Sunday, matching
  `Date.day_of_week/1`. Without `localize`, callers pass `1` (Monday), which
  is the ISO 8601 default.
  """

  alias Flicker.Facet.Range

  @typedoc "A day-of-week number, `1` (Monday) through `7` (Sunday)."
  @type day_of_week :: 1..7

  @typedoc "A semantic date preset."
  @type t :: %__MODULE__{
          id: atom(),
          token: String.t(),
          label: String.t(),
          resolve: (Date.t(), day_of_week() -> {Date.t() | nil, Date.t() | nil})
        }

  @enforce_keys [:id, :token, :label, :resolve]
  defstruct [:id, :token, :label, :resolve]

  @doc """
  The built-in preset table, in display order.

  ## Examples

      iex> Flicker.Facet.Preset.builtin() |> Enum.map(& &1.token) |> Enum.take(3)
      ["today", "yesterday", "last-7-days"]
  """
  @spec builtin() :: [t()]
  def builtin do
    [
      preset(:today, "today", "Today", fn today, _week_start -> {today, today} end),
      preset(:yesterday, "yesterday", "Yesterday", fn today, _week_start ->
        {Date.add(today, -1), Date.add(today, -1)}
      end),
      last_n_days(:last_7_days, "last-7-days", "Last 7 days", 7),
      last_n_days(:last_30_days, "last-30-days", "Last 30 days", 30),
      last_n_days(:last_60_days, "last-60-days", "Last 60 days", 60),
      last_n_days(:last_90_days, "last-90-days", "Last 90 days", 90),
      preset(:this_week, "this-week", "This week", fn today, week_start ->
        start = week_start(today, week_start)
        {start, Date.add(start, 6)}
      end),
      preset(:last_week, "last-week", "Last week", fn today, week_start ->
        start = today |> week_start(week_start) |> Date.add(-7)
        {start, Date.add(start, 6)}
      end),
      preset(:this_month, "this-month", "This month", fn today, _week_start ->
        {Date.beginning_of_month(today), Date.end_of_month(today)}
      end),
      preset(:last_month, "last-month", "Last month", fn today, _week_start ->
        previous = today |> Date.beginning_of_month() |> Date.add(-1)
        {Date.beginning_of_month(previous), Date.end_of_month(previous)}
      end),
      preset(:in_the_last_month, "in-the-last-month", "In the last month", fn today, _week_start ->
        {shift_months(today, -1), today}
      end),
      preset(:this_quarter, "this-quarter", "This quarter", fn today, _week_start ->
        quarter_start = %{today | month: div(today.month - 1, 3) * 3 + 1, day: 1}
        {quarter_start, quarter_start |> shift_months(2) |> Date.end_of_month()}
      end),
      preset(:year_to_date, "year-to-date", "Year to date", fn today, _week_start ->
        {%{today | month: 1, day: 1}, today}
      end),
      preset(:all_time, "all-time", "All time", fn _today, _week_start -> {nil, nil} end)
    ]
  end

  defp preset(id, token, label, resolve) do
    %__MODULE__{id: id, token: token, label: label, resolve: resolve}
  end

  # "Last 7 days" is inclusive of today: 6 days back plus today.
  defp last_n_days(id, token, label, days) do
    preset(id, token, label, fn today, _week_start -> {Date.add(today, -(days - 1)), today} end)
  end

  defp week_start(date, first_day_of_week) do
    Date.add(date, -Integer.mod(Date.day_of_week(date) - first_day_of_week, 7))
  end

  # Calendar-aware month arithmetic that clamps rather than rolling over:
  # one month before March 31st is February 28th (or 29th), not March 3rd.
  defp shift_months(date, months) do
    total = date.year * 12 + (date.month - 1) + months
    year = div(total, 12)
    month = Integer.mod(total, 12) + 1
    day = min(date.day, Date.days_in_month(%{date | year: year, month: month, day: 1}))

    %{date | year: year, month: month, day: day}
  end

  @doc """
  Finds a preset by its typed token, case-sensitively.

  ## Examples

      iex> Flicker.Facet.Preset.find_by_token("last-30-days").id
      :last_30_days

      iex> Flicker.Facet.Preset.find_by_token("Last-30-Days")
      nil

      iex> Flicker.Facet.Preset.find_by_token("nope")
      nil
  """
  @spec find_by_token(String.t(), [t()]) :: t() | nil
  def find_by_token(token, presets \\ builtin()) do
    Enum.find(presets, &(&1.token == token))
  end

  @doc """
  Finds a preset by its canonical id.

  ## Examples

      iex> Flicker.Facet.Preset.find_by_id(:all_time).token
      "all-time"

      iex> Flicker.Facet.Preset.find_by_id(:nope)
      nil
  """
  @spec find_by_id(atom(), [t()]) :: t() | nil
  def find_by_id(id, presets \\ builtin()) do
    Enum.find(presets, &(&1.id == id))
  end

  @doc """
  Resolves `preset` against a reference date and the locale's first day of
  week, returning a `Flicker.Facet.Range` tagged with the preset's id.

  ## Examples

      iex> preset = Flicker.Facet.Preset.find_by_id(:last_7_days)
      ...> Flicker.Facet.Preset.resolve(preset, ~D[2026-07-28], 1)
      %Flicker.Facet.Range{from: ~D[2026-07-22], to: ~D[2026-07-28], preset: :last_7_days}

      iex> preset = Flicker.Facet.Preset.find_by_id(:this_week)
      ...> Flicker.Facet.Preset.resolve(preset, ~D[2026-07-29], 1).from
      ~D[2026-07-27]

      iex> preset = Flicker.Facet.Preset.find_by_id(:this_week)
      ...> Flicker.Facet.Preset.resolve(preset, ~D[2026-07-29], 7).from
      ~D[2026-07-26]

      iex> preset = Flicker.Facet.Preset.find_by_id(:all_time)
      ...> Flicker.Facet.Preset.resolve(preset, ~D[2026-07-28], 1)
      %Flicker.Facet.Range{from: nil, to: nil, preset: :all_time}
  """
  @spec resolve(t(), Date.t(), day_of_week()) :: Range.t()
  def resolve(%__MODULE__{id: id, resolve: resolve}, reference_date, first_day_of_week) do
    {from, to} = resolve.(reference_date, first_day_of_week)

    %Range{from: from, to: to, preset: id}
  end
end
