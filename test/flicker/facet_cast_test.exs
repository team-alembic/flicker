defmodule Flicker.FacetCastTest do
  @moduledoc """
  Value casting and validation for every facet type (Spec 018).

  Every test fixes the reference date via the `:today` opt — `cast/4` takes it
  as an argument rather than reading the clock precisely so relative dates and
  presets are pinnable.
  """

  use ExUnit.Case, async: true

  alias Flicker.Facet
  alias Flicker.Facet.{Cast, Range}

  doctest Flicker.Facet.Cast
  doctest Flicker.Facet

  @today ~D[2026-07-29]
  @opts [today: @today]

  defp cast(facet, raw, op \\ nil) do
    Facet.cast_value(facet, raw, op || facet.default_op, @opts)
  end

  describe ":integer / :float" do
    setup do
      %{int: Facet.new(key: :count, type: :integer), float: Facet.new(key: :ratio, type: :float)}
    end

    test "casts a clean integer", %{int: facet} do
      assert cast(facet, "42") == {:ok, :eq, 42}
      assert cast(facet, "-7") == {:ok, :eq, -7}
    end

    test "rejects anything with trailing junk", %{int: facet} do
      assert cast(facet, "42x") == {:error, {:bad_integer, %{value: "42x"}}}
      assert cast(facet, "abc") == {:error, {:bad_integer, %{value: "abc"}}}
      assert cast(facet, "") == {:error, {:bad_integer, %{value: ""}}}
    end

    test "casts floats, and widens a bare integer to one", %{float: facet} do
      assert cast(facet, "1.5") == {:ok, :eq, 1.5}
      assert cast(facet, "2") == {:ok, :eq, 2.0}
    end

    test "rejects a malformed float", %{float: facet} do
      assert cast(facet, "1.2.3") == {:error, {:bad_float, %{value: "1.2.3"}}}
    end
  end

  describe ":boolean" do
    setup do: %{facet: Facet.new(key: :verified?, type: :boolean)}

    test "casts either literal, case-insensitively", %{facet: facet} do
      assert cast(facet, "true") == {:ok, :eq, true}
      assert cast(facet, "TRUE") == {:ok, :eq, true}
      assert cast(facet, "false") == {:ok, :eq, false}
    end

    test "rejects anything else", %{facet: facet} do
      assert cast(facet, "yes") == {:error, {:bad_boolean, %{value: "yes"}}}
    end
  end

  describe ":date" do
    setup do: %{facet: Facet.new(key: :created, type: :date)}

    test "casts ISO 8601", %{facet: facet} do
      assert cast(facet, "2026-07-01") == {:ok, :eq, ~D[2026-07-01]}
    end

    test "casts named dates against the reference date", %{facet: facet} do
      assert cast(facet, "today") == {:ok, :eq, @today}
      assert cast(facet, "yesterday") == {:ok, :eq, ~D[2026-07-28]}
    end

    test "casts relative day and week offsets backwards", %{facet: facet} do
      assert cast(facet, "7d") == {:ok, :eq, ~D[2026-07-22]}
      assert cast(facet, "2w") == {:ok, :eq, ~D[2026-07-15]}
    end

    test "casts month and year offsets by calendar, not by 30/365 days", %{facet: facet} do
      assert cast(facet, "1m") == {:ok, :eq, ~D[2026-06-29]}
      assert cast(facet, "1y") == {:ok, :eq, ~D[2025-07-29]}
    end

    test "clamps a month offset rather than rolling over a short month", %{facet: facet} do
      assert Facet.cast_value(facet, "1m", :eq, today: ~D[2026-03-31]) == {:ok, :eq, ~D[2026-02-28]}
    end

    test "rejects an impossible or malformed date", %{facet: facet} do
      assert cast(facet, "2026-13-01") == {:error, {:bad_date, %{value: "2026-13-01"}}}
      assert cast(facet, "2026-02-30") == {:error, {:bad_date, %{value: "2026-02-30"}}}
      assert cast(facet, "nonsense") == {:error, {:bad_date, %{value: "nonsense"}}}
    end
  end

  describe ":datetime" do
    setup do: %{facet: Facet.new(key: :at, type: :datetime)}

    test "casts a full ISO 8601 instant with an explicit offset", %{facet: facet} do
      assert cast(facet, "2026-07-01T09:30:00Z") == {:ok, :eq, ~U[2026-07-01 09:30:00Z]}
    end

    test "casts a bare date to midnight UTC", %{facet: facet} do
      assert cast(facet, "2026-07-01") == {:ok, :eq, ~U[2026-07-01 00:00:00Z]}
    end

    test "casts named and relative dates to midnight UTC", %{facet: facet} do
      assert cast(facet, "today") == {:ok, :eq, ~U[2026-07-29 00:00:00Z]}
    end

    test "rejects a malformed instant", %{facet: facet} do
      assert cast(facet, "not-a-time") == {:error, {:bad_datetime, %{value: "not-a-time"}}}
    end
  end

  describe ":duration" do
    setup do: %{facet: Facet.new(key: :length, type: :duration)}

    test "casts single units to seconds", %{facet: facet} do
      assert cast(facet, "90s") == {:ok, :eq, 90}
      assert cast(facet, "15m") == {:ok, :eq, 900}
      assert cast(facet, "2h") == {:ok, :eq, 7_200}
      assert cast(facet, "1d") == {:ok, :eq, 86_400}
    end

    test "sums compound durations", %{facet: facet} do
      assert cast(facet, "2h30m") == {:ok, :eq, 9_000}
      assert cast(facet, "1d2h30m15s") == {:ok, :eq, 95_415}
    end

    test "rejects out-of-order or repeated units rather than guessing", %{facet: facet} do
      assert cast(facet, "30m2h") == {:error, {:bad_duration, %{value: "30m2h"}}}
      assert cast(facet, "2h2h") == {:error, {:bad_duration, %{value: "2h2h"}}}
    end

    test "rejects junk", %{facet: facet} do
      assert cast(facet, "2hours") == {:error, {:bad_duration, %{value: "2hours"}}}
      assert cast(facet, "abc") == {:error, {:bad_duration, %{value: "abc"}}}
      assert cast(facet, "") == {:error, {:bad_duration, %{value: ""}}}
    end
  end

  describe ":enum" do
    setup do: %{facet: Facet.new(key: :status, type: :enum, values: [:active, :inactive])}

    test "casts a member", %{facet: facet} do
      assert cast(facet, "active") == {:ok, :eq, :active}
    end

    test "rejects a non-member, carrying the closed set for a correction", %{facet: facet} do
      assert cast(facet, "activ") ==
               {:error, {:not_in_values, %{value: "activ", values: [:active, :inactive]}}}
    end
  end

  describe "range literals" do
    setup do: %{facet: Facet.new(key: :created, type: :date_range)}

    test "casts a closed range", %{facet: facet} do
      assert cast(facet, "2026-06-01..2026-06-30") ==
               {:ok, :between, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}}
    end

    test "casts half-open ranges in both directions", %{facet: facet} do
      assert cast(facet, "..2026-06-30") == {:ok, :between, %Range{from: nil, to: ~D[2026-06-30]}}
      assert cast(facet, "2026-06-01..") == {:ok, :between, %Range{from: ~D[2026-06-01], to: nil}}
    end

    test "casts a bare scalar to a single-day range", %{facet: facet} do
      assert cast(facet, "2026-07-01") ==
               {:ok, :between, %Range{from: ~D[2026-07-01], to: ~D[2026-07-01]}}
    end

    test "accepts relative and named endpoints", %{facet: facet} do
      assert cast(facet, "7d..today") ==
               {:ok, :between, %Range{from: ~D[2026-07-22], to: @today}}
    end

    test "rejects a reversed range, naming both endpoints", %{facet: facet} do
      assert cast(facet, "2026-07-30..2026-07-01") ==
               {:error, {:reversed_range, %{from: ~D[2026-07-30], to: ~D[2026-07-01]}}}
    end

    test "an equal-endpoint range is not reversed", %{facet: facet} do
      assert {:ok, :between, %Range{}} = cast(facet, "2026-07-01..2026-07-01")
    end

    test "rejects a bare `..` with neither endpoint", %{facet: facet} do
      assert cast(facet, "..") == {:error, {:incomplete_range, %{value: ".."}}}
    end

    test "rejects a malformed endpoint rather than dropping it", %{facet: facet} do
      assert cast(facet, "2026-06-01..nonsense") == {:error, {:bad_date, %{value: "nonsense"}}}
      # Only the first `..` splits, so `1` is the from-endpoint and fails
      # first — a malformed range never silently drops a component.
      assert cast(facet, "1..2..3") == {:error, {:bad_date, %{value: "1"}}}
    end
  end

  describe "date presets" do
    setup do: %{facet: Facet.new(key: :created, type: :date_range)}

    test "a preset token resolves and is tagged with its id", %{facet: facet} do
      assert cast(facet, "last-30-days") ==
               {:ok, :between, %Range{from: ~D[2026-06-30], to: @today, preset: :last_30_days}}
    end

    test "all-time is an unbounded range, not an error", %{facet: facet} do
      assert cast(facet, "all-time") ==
               {:ok, :between, %Range{from: nil, to: nil, preset: :all_time}}
    end

    test "week-sensitive presets honour the first day of week" do
      facet = Facet.new(key: :created, type: :date_range)

      {:ok, :between, monday} = Facet.cast_value(facet, "this-week", :between, today: @today, first_day_of_week: 1)
      {:ok, :between, sunday} = Facet.cast_value(facet, "this-week", :between, today: @today, first_day_of_week: 7)

      assert monday.from == ~D[2026-07-27]
      assert sunday.from == ~D[2026-07-26]
    end

    test "defaults to Monday when no first day of week is given", %{facet: facet} do
      assert {:ok, :between, %Range{from: ~D[2026-07-27]}} = cast(facet, "this-week")
    end

    test "presets are not consulted for a numeric range" do
      facet = Facet.new(key: :price, type: :number_range)

      assert cast(facet, "last-30-days") == {:error, {:bad_integer, %{value: "last-30-days"}}}
    end

    test "a facet may restrict its own preset list" do
      facet = Facet.new(key: :created, type: :date_range, presets: [Flicker.Facet.Preset.find_by_id(:today)])

      assert {:ok, :between, %Range{preset: :today}} = cast(facet, "today")
      assert {:error, {:bad_date, _}} = cast(facet, "last-30-days")
    end
  end

  describe "numeric ranges and bounds" do
    test "casts integer endpoints" do
      facet = Facet.new(key: :price, type: :number_range)

      assert cast(facet, "10..50") == {:ok, :between, %Range{from: 10, to: 50}}
    end

    test "casts float endpoints when the scalar says so" do
      facet = Facet.new(key: :price, type: :number_range, scalar: :float)

      assert cast(facet, "1.5..2.5") == {:ok, :between, %Range{from: 1.5, to: 2.5}}
    end

    test "rejects a reversed numeric range" do
      facet = Facet.new(key: :price, type: :number_range)

      assert cast(facet, "50..10") == {:error, {:reversed_range, %{from: 50, to: 10}}}
    end

    test "rejects an endpoint outside the facet's bounds" do
      facet = Facet.new(key: :price, type: :number_range, bounds: %{min: 0, max: 500})

      assert cast(facet, "10..900") == {:error, {:out_of_bounds, %{min: 0, max: 500, value: 900}}}
      assert cast(facet, "-5..10") == {:error, {:out_of_bounds, %{min: 0, max: 500, value: -5}}}
    end

    test "bounds apply to plain numeric facets too" do
      facet = Facet.new(key: :price, type: :integer, bounds: %{min: 0, max: 100})

      assert cast(facet, "50") == {:ok, :eq, 50}
      assert cast(facet, "900") == {:error, {:out_of_bounds, %{min: 0, max: 100, value: 900}}}
    end

    test "a one-sided bound only constrains that side" do
      facet = Facet.new(key: :price, type: :integer, bounds: %{min: 0})

      assert cast(facet, "9999") == {:ok, :eq, 9999}
      assert {:error, {:out_of_bounds, _}} = cast(facet, "-1")
    end

    test "an open endpoint is never out of bounds" do
      facet = Facet.new(key: :price, type: :number_range, bounds: %{min: 0, max: 500})

      assert {:ok, :between, %Range{from: 10, to: nil}} = cast(facet, "10..")
    end
  end

  describe "datetime ranges" do
    setup do: %{facet: Facet.new(key: :at, type: :datetime_range)}

    test "a bare date spans that whole UTC day", %{facet: facet} do
      assert cast(facet, "2026-07-01") ==
               {:ok, :between, %Range{from: ~U[2026-07-01 00:00:00Z], to: ~U[2026-07-01 23:59:59.999999Z]}}
    end

    test "an explicit instant is left exactly as given", %{facet: facet} do
      assert cast(facet, "2026-07-01T09:30:00Z..2026-07-01T17:00:00Z") ==
               {:ok, :between, %Range{from: ~U[2026-07-01 09:30:00Z], to: ~U[2026-07-01 17:00:00Z]}}
    end

    test "the upper endpoint of a date-only range expands to end of day", %{facet: facet} do
      assert {:ok, :between, %Range{to: ~U[2026-06-30 23:59:59.999999Z]}} =
               cast(facet, "2026-06-01..2026-06-30")
    end
  end

  describe "list literals" do
    setup do
      %{facet: Facet.new(key: :status, type: :enum, values: [:active, :inactive, :archived], multiple?: true)}
    end

    test "casts a comma-separated list to :in", %{facet: facet} do
      assert cast(facet, "active,inactive") == {:ok, :in, [:active, :inactive]}
    end

    test "preserves element order", %{facet: facet} do
      assert cast(facet, "archived,active") == {:ok, :in, [:archived, :active]}
    end

    test "!= becomes :not_in", %{facet: facet} do
      assert Facet.cast_value(facet, "active,inactive", :neq, @opts) == {:ok, :not_in, [:active, :inactive]}
    end

    test "a single element keeps the scalar operator and a bare value", %{facet: facet} do
      assert cast(facet, "active") == {:ok, :eq, :active}
      assert Facet.cast_value(facet, "active", :neq, @opts) == {:ok, :neq, :active}
    end

    test "rejects an empty element — the mid-typing state", %{facet: facet} do
      assert cast(facet, "active,") == {:error, {:incomplete_list, %{value: "active,"}}}
      assert cast(facet, "active,,inactive") == {:error, {:incomplete_list, %{value: "active,,inactive"}}}
    end

    test "rejects the whole list if any element is invalid", %{facet: facet} do
      assert cast(facet, "active,nope") ==
               {:error, {:not_in_values, %{value: "nope", values: [:active, :inactive, :archived]}}}
    end

    test "a facet without multiple? treats a comma as part of the value" do
      facet = Facet.new(key: :name, type: :string)

      assert cast(facet, "Nguyen, Casey") == {:ok, :eq, "Nguyen, Casey"}
    end
  end

  describe "the :validate escape hatch" do
    test "runs after a successful cast, on the cast value" do
      facet =
        Facet.new(
          key: :price,
          type: :integer,
          validate: fn value -> if rem(value, 2) == 0, do: :ok, else: {:error, "must be even"} end
        )

      assert cast(facet, "10") == {:ok, :eq, 10}
      assert cast(facet, "11") == {:error, {:custom, %{message: "must be even"}}}
    end

    test "does not run when the cast itself failed" do
      facet = Facet.new(key: :price, type: :integer, validate: fn _value -> raise "should not run" end)

      assert cast(facet, "abc") == {:error, {:bad_integer, %{value: "abc"}}}
    end

    test "accepts a structured reason as-is" do
      facet = Facet.new(key: :price, type: :integer, validate: fn _v -> {:error, {:too_big, %{limit: 5}}} end)

      assert cast(facet, "10") == {:error, {:too_big, %{limit: 5}}}
    end

    test "receives a Range for a range facet" do
      facet =
        Facet.new(
          key: :created,
          type: :date_range,
          validate: fn %Range{from: from, to: to} ->
            if Date.diff(to, from) > 30, do: {:error, "at most 30 days"}, else: :ok
          end
        )

      assert {:ok, :between, %Range{}} = cast(facet, "2026-07-01..2026-07-10")
      assert cast(facet, "2026-01-01..2026-12-31") == {:error, {:custom, %{message: "at most 30 days"}}}
    end

    test "a facet with no validator is unaffected" do
      assert cast(Facet.new(key: :price, type: :integer), "10") == {:ok, :eq, 10}
    end
  end

  describe "validate/4" do
    test "mirrors cast/4's verdict without the value" do
      facet = Facet.new(key: :price, type: :integer)

      assert Facet.validate_value(facet, "10", :eq, @opts) == :ok
      assert Facet.validate_value(facet, "abc", :eq, @opts) == {:error, {:bad_integer, %{value: "abc"}}}
    end
  end

  describe "totality" do
    test "never raises for any facet type against arbitrary input" do
      facets = [
        Facet.new(key: :a, type: :string),
        Facet.new(key: :b, type: :integer),
        Facet.new(key: :c, type: :float),
        Facet.new(key: :d, type: :boolean),
        Facet.new(key: :e, type: :date),
        Facet.new(key: :f, type: :datetime),
        Facet.new(key: :g, type: :duration),
        Facet.new(key: :h, type: :enum, values: [:one]),
        Facet.new(key: :i, type: :date_range),
        Facet.new(key: :j, type: :datetime_range),
        Facet.new(key: :k, type: :number_range),
        Facet.new(key: :l, type: :enum, values: [:one], multiple?: true)
      ]

      inputs = [
        "",
        "..",
        "...",
        ",",
        ",,",
        "..,..",
        "1..",
        "..1",
        "1..2..3",
        "-",
        "abc",
        "😀",
        "2026-",
        "2026-07-01T",
        "true",
        "0",
        String.duplicate("9", 400),
        "one,one,one",
        "\\",
        "\"",
        "last-30-days",
        "today..",
        "..today"
      ]

      for facet <- facets, input <- inputs do
        result = Cast.cast(facet, input, facet.default_op, today: @today)

        assert match?({:ok, _op, _value}, result) or
                 match?({:error, {reason, params}} when is_atom(reason) and is_map(params), result),
               "#{facet.type} / #{inspect(input)} returned #{inspect(result)}"
      end
    end
  end
end
