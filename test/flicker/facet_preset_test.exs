defmodule Flicker.FacetPresetTest do
  @moduledoc """
  The built-in date presets (Spec 018). Every case fixes both the reference
  date *and* the first day of week, since `resolve/3` takes both as arguments
  precisely so it never depends on today or on an ambient locale.
  """

  use ExUnit.Case, async: true

  alias Flicker.Facet.{Preset, Range}

  doctest Flicker.Facet.Preset
  doctest Flicker.Facet.Range

  # A Wednesday, deliberately: mid-week, mid-month, mid-quarter, so no
  # boundary case passes by accident.
  @today ~D[2026-07-29]
  @monday 1
  @sunday 7

  defp resolve(id, week_start \\ @monday, today \\ @today) do
    id |> Preset.find_by_id() |> Preset.resolve(today, week_start)
  end

  describe "the table itself" do
    test "every preset has a unique id and token" do
      presets = Preset.builtin()

      assert length(Enum.uniq_by(presets, & &1.id)) == length(presets)
      assert length(Enum.uniq_by(presets, & &1.token)) == length(presets)
    end

    test "every token is kebab-case and every id is the snake_case of it" do
      for %Preset{id: id, token: token} <- Preset.builtin() do
        assert token =~ ~r/^[a-z0-9]+(-[a-z0-9]+)*$/, "#{token} is not kebab-case"
        assert Atom.to_string(id) == String.replace(token, "-", "_")
      end
    end

    test "every preset resolves to a Range tagged with its own id" do
      for %Preset{id: id} <- Preset.builtin() do
        assert %Range{preset: ^id} = resolve(id)
      end
    end

    test "every preset except all-time resolves to a chronological range" do
      for %Preset{id: id} <- Preset.builtin(), id != :all_time do
        %Range{from: from, to: to} = resolve(id)

        refute is_nil(from), "#{id} produced an open lower bound"
        refute is_nil(to), "#{id} produced an open upper bound"
        assert Date.compare(from, to) in [:lt, :eq], "#{id} produced a reversed range"
      end
    end

    test "find_by_token and find_by_id agree" do
      for %Preset{id: id, token: token} <- Preset.builtin() do
        assert Preset.find_by_token(token).id == id
        assert Preset.find_by_id(id).token == token
      end
    end
  end

  describe "day presets" do
    test "today is a single day" do
      assert resolve(:today) == %Range{from: @today, to: @today, preset: :today}
      assert Range.single?(resolve(:today))
    end

    test "yesterday is the single preceding day" do
      assert resolve(:yesterday) == %Range{
               from: ~D[2026-07-28],
               to: ~D[2026-07-28],
               preset: :yesterday
             }
    end
  end

  describe "last-N-days presets are inclusive of today" do
    test "last-7-days spans exactly 7 days ending today" do
      %Range{from: from, to: to} = resolve(:last_7_days)

      assert to == @today
      assert Date.diff(to, from) == 6
    end

    test "last-30/60/90 span exactly 30/60/90 days" do
      for {id, days} <- [last_30_days: 30, last_60_days: 60, last_90_days: 90] do
        %Range{from: from, to: to} = resolve(id)

        assert to == @today
        assert Date.diff(to, from) == days - 1, "#{id} spanned the wrong number of days"
      end
    end
  end

  describe "week presets honour the locale's first day of week" do
    test "this-week starts Monday for a Monday-start locale" do
      assert resolve(:this_week, @monday) == %Range{
               from: ~D[2026-07-27],
               to: ~D[2026-08-02],
               preset: :this_week
             }
    end

    test "this-week starts Sunday for a Sunday-start locale" do
      assert resolve(:this_week, @sunday) == %Range{
               from: ~D[2026-07-26],
               to: ~D[2026-08-01],
               preset: :this_week
             }
    end

    test "last-week is the seven days before this-week, under either convention" do
      for week_start <- [@monday, @sunday] do
        %Range{from: this_from} = resolve(:this_week, week_start)
        %Range{from: last_from, to: last_to} = resolve(:last_week, week_start)

        assert Date.diff(this_from, last_from) == 7
        assert Date.diff(last_to, last_from) == 6
        assert Date.diff(this_from, last_to) == 1
      end
    end

    test "the two conventions genuinely disagree at the same reference date" do
      refute resolve(:this_week, @monday) == resolve(:this_week, @sunday)
    end

    test "a reference date that is itself the week's first day starts that day" do
      # 2026-07-27 is a Monday.
      assert resolve(:this_week, @monday, ~D[2026-07-27]).from == ~D[2026-07-27]
    end
  end

  describe "month presets" do
    test "this-month spans the whole calendar month" do
      assert resolve(:this_month) == %Range{
               from: ~D[2026-07-01],
               to: ~D[2026-07-31],
               preset: :this_month
             }
    end

    test "last-month spans the whole preceding calendar month" do
      assert resolve(:last_month) == %Range{
               from: ~D[2026-06-01],
               to: ~D[2026-06-30],
               preset: :last_month
             }
    end

    test "last-month handles a January reference date by crossing the year" do
      assert resolve(:last_month, @monday, ~D[2026-01-15]) == %Range{
               from: ~D[2025-12-01],
               to: ~D[2025-12-31],
               preset: :last_month
             }
    end

    test "in-the-last-month is a rolling month back from today, not a calendar one" do
      assert resolve(:in_the_last_month) == %Range{
               from: ~D[2026-06-29],
               to: @today,
               preset: :in_the_last_month
             }
    end

    test "in-the-last-month clamps rather than rolling over a short month" do
      # One month before March 31st is February 28th, not March 3rd.
      assert resolve(:in_the_last_month, @monday, ~D[2026-03-31]).from == ~D[2026-02-28]
    end

    test "in-the-last-month clamps to February 29th in a leap year" do
      assert resolve(:in_the_last_month, @monday, ~D[2024-03-31]).from == ~D[2024-02-29]
    end
  end

  describe "quarter and year presets" do
    test "this-quarter spans Q3 for a July reference date" do
      assert resolve(:this_quarter) == %Range{
               from: ~D[2026-07-01],
               to: ~D[2026-09-30],
               preset: :this_quarter
             }
    end

    test "this-quarter is correct in every quarter" do
      for {date, expected} <- [
            {~D[2026-01-15], {~D[2026-01-01], ~D[2026-03-31]}},
            {~D[2026-04-15], {~D[2026-04-01], ~D[2026-06-30]}},
            {~D[2026-07-15], {~D[2026-07-01], ~D[2026-09-30]}},
            {~D[2026-11-15], {~D[2026-10-01], ~D[2026-12-31]}}
          ] do
        {from, to} = expected
        assert resolve(:this_quarter, @monday, date) == %Range{from: from, to: to, preset: :this_quarter}
      end
    end

    test "year-to-date runs from January 1st to today" do
      assert resolve(:year_to_date) == %Range{
               from: ~D[2026-01-01],
               to: @today,
               preset: :year_to_date
             }
    end
  end

  describe "all-time" do
    test "is unbounded on both ends, and says so" do
      range = resolve(:all_time)

      assert range == %Range{from: nil, to: nil, preset: :all_time}
      assert Range.unbounded?(range)
    end
  end

  describe "Range helpers" do
    test "unbounded? is only true when both endpoints are open" do
      assert Range.unbounded?(%Range{})
      refute Range.unbounded?(%Range{from: 10})
      refute Range.unbounded?(%Range{to: 10})
      refute Range.unbounded?(%Range{from: 1, to: 10})
    end

    test "single? needs both endpoints present and equal" do
      assert Range.single?(%Range{from: 10, to: 10})
      assert Range.single?(%Range{from: ~D[2026-07-01], to: ~D[2026-07-01]})
      refute Range.single?(%Range{from: 10, to: 11})
      refute Range.single?(%Range{from: 10})
      refute Range.single?(%Range{to: 10})
      refute Range.single?(%Range{})
    end
  end
end
