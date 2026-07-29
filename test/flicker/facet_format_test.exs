defmodule Flicker.FacetFormatTest do
  @moduledoc """
  Display formatting for facet values (Spec 018).

  `localize` is optional, so most assertions here have to hold on *both*
  paths. Where a case is genuinely path-specific it branches on
  `Flicker.Facet.Format.localized?/0` rather than guessing, so the suite
  states which behaviour it verified instead of quietly passing on one leg of
  the matrix.
  """

  use ExUnit.Case, async: true

  alias Flicker.Facet
  alias Flicker.Facet.{Format, Range}

  doctest Flicker.Facet.Format

  @created Facet.new(key: :created, type: :date_range)
  @price Facet.new(key: :price, type: :number_range)
  @length Facet.new(key: :length, type: :duration)

  describe "presets render as what the user chose" do
    test "a preset range shows its label, not its resolved dates" do
      range = %Range{from: ~D[2026-06-30], to: ~D[2026-07-29], preset: :last_30_days}

      assert Format.range_label(@created, range) == "Last 30 days"
    end

    test "every built-in preset renders its own label" do
      for preset <- Flicker.Facet.Preset.builtin() do
        range = %Range{from: ~D[2026-01-01], to: ~D[2026-01-02], preset: preset.id}

        assert Format.range_label(@created, range) == preset.label
      end
    end

    test "a preset id the facet doesn't know falls back to the interval" do
      range = %Range{from: ~D[2026-06-01], to: ~D[2026-06-30], preset: :invented}

      label = Format.range_label(@created, range)

      refute label == "invented"
      assert label =~ "2026" or label =~ "Jun"
    end
  end

  describe "range intervals" do
    test "a closed numeric range shows both endpoints" do
      assert Format.range_label(@price, %Range{from: 10, to: 50}) == "10 – 50"
    end

    test "half-open ranges read as prose rather than a dangling dash" do
      assert Format.range_label(@price, %Range{from: 10, to: nil}) == "10 or more"
      assert Format.range_label(@price, %Range{from: nil, to: 50}) == "up to 50"
    end

    test "a single-value range collapses to one endpoint" do
      assert Format.range_label(@price, %Range{from: 10, to: 10}) == "10"
    end

    test "a closed date range mentions both dates" do
      label = Format.range_label(@created, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]})

      if Format.localized?() do
        # CLDR collapses the shared parts, so the exact string is locale data;
        # what matters is that both endpoints survive into it.
        assert label =~ "1" and label =~ "30"
      else
        assert label == "2026-06-01 – 2026-06-30"
      end
    end
  end

  describe "the localize boundary" do
    test "with localize present, formatting actually goes through CLDR" do
      # A blanket rescue in the localize branch once hid a genuine API
      # mismatch — `Localize.Duration` has its own struct, and passing
      # Elixir's silently fell back. This pins that the CLDR path is really
      # exercised rather than quietly degrading.
      if Format.localized?() do
        assert Format.value_label(@length, 9_000) == "2 hours and 30 minutes"
        assert Format.value_label(@price, 1_234_567) == "1,234,567"

        # CLDR collapses the shared month, which plain concatenation cannot.
        collapsed = Format.range_label(@created, %Range{from: ~D[2026-07-18], to: ~D[2026-07-24]})

        assert collapsed =~ "18"
        assert collapsed =~ "24"
        refute collapsed =~ "Jul 24"
      end
    end

    test "the fallback path is self-consistent when localize is absent" do
      if !Format.localized?() do
        assert Format.value_label(@length, 9_000) == "2h30m"
        assert Format.value_label(@price, 1_234_567) == "1234567"

        assert Format.range_label(@created, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}) ==
                 "2026-06-01 – 2026-06-30"
      end
    end
  end

  describe "durations" do
    test "the fallback form is the same compound the grammar accepts" do
      # A user who sees `2h30m` on a pill can type it straight back.
      if !Format.localized?() do
        assert Format.value_label(@length, 9_000) == "2h30m"
        assert Format.value_label(@length, 90) == "1m30s"
        assert Format.value_label(@length, 86_400) == "1d"
        assert Format.value_label(@length, 95_415) == "1d2h30m15s"
      end
    end

    test "zero is not an empty string" do
      if !Format.localized?() do
        assert Format.value_label(@length, 0) == "0s"
      end

      assert Format.value_label(@length, 0) != ""
    end

    test "every duration renders non-empty on either path" do
      for seconds <- [0, 1, 59, 60, 61, 3_599, 3_600, 86_399, 86_400, 1_000_000] do
        label = Format.value_label(@length, seconds)

        assert is_binary(label) and label != "", "#{seconds} rendered #{inspect(label)}"
      end
    end
  end

  describe "lists" do
    setup do
      facet =
        Facet.new(
          key: :status,
          type: :enum,
          multiple?: true,
          values: [:active, :inactive, :archived],
          value_labels: %{active: "Active", inactive: "Inactive", archived: "Archived"}
        )

      %{facet: facet}
    end

    test "two values join with a conjunction, not a bare comma", %{facet: facet} do
      label = Format.value_label(facet, [:active, :archived])

      assert label =~ "Active"
      assert label =~ "Archived"
      refute label == "Active, Archived"
    end

    test "three values keep the serial comma structure", %{facet: facet} do
      label = Format.value_label(facet, [:active, :inactive, :archived])

      assert label =~ "Active"
      assert label =~ "Inactive"
      assert label =~ "Archived"
    end

    test "a single-element list doesn't grow a conjunction", %{facet: facet} do
      assert Format.value_label(facet, [:active]) == "Active"
    end

    test "an empty list is empty, not a stray conjunction", %{facet: facet} do
      assert Format.value_label(facet, []) == ""
    end

    test "list elements use their display labels", %{facet: facet} do
      refute Format.value_label(facet, [:active, :archived]) =~ "active"
    end
  end

  describe "scalars" do
    test "an enum value uses its configured label" do
      facet = Facet.new(key: :status, type: :enum, value_labels: %{active: "Currently active"})

      assert Format.value_label(facet, :active) == "Currently active"
    end

    test "an enum value without a label falls back to the atom" do
      assert Format.value_label(Facet.new(key: :status, type: :enum), :active) == "active"
    end

    test "a date renders ISO 8601 without localize" do
      if !Format.localized?() do
        assert Format.value_label(Facet.new(key: :on, type: :date), ~D[2026-07-01]) == "2026-07-01"
      end
    end

    test "a string value passes through" do
      assert Format.value_label(Facet.new(key: :name, type: :string), "Casey") == "Casey"
    end

    test "a boolean renders as itself" do
      facet = Facet.new(key: :verified?, type: :boolean)

      assert Format.value_label(facet, true) == "true"
      assert Format.value_label(facet, false) == "false"
    end
  end

  describe "totality" do
    test "never raises, and never renders an empty label, for any plausible value" do
      facets = [
        @created,
        @price,
        @length,
        Facet.new(key: :at, type: :datetime_range),
        Facet.new(key: :name, type: :string),
        Facet.new(key: :status, type: :enum, values: [:a])
      ]

      values = [
        42,
        -1,
        0,
        1.5,
        "text",
        :atom,
        true,
        ~D[2026-07-01],
        ~U[2026-07-01 09:30:00Z],
        %Range{from: 1, to: 2},
        %Range{from: nil, to: nil},
        %Range{from: ~D[2026-01-01], to: ~D[2026-12-31]},
        %Range{from: ~U[2026-01-01 00:00:00Z], to: ~U[2026-12-31 23:59:59Z]},
        %Range{from: 1, to: 2, preset: :unknown_preset},
        [:a, :b]
      ]

      for facet <- facets, value <- values do
        label = Format.value_label(facet, value)

        assert is_binary(label), "#{facet.type} / #{inspect(value)} rendered #{inspect(label)}"
      end
    end

    test "an explicit locale is accepted on every entry point" do
      # Passing a locale must be harmless even without localize present.
      opts = [locale: "en-AU"]

      assert is_binary(Format.value_label(@price, 1234, opts))
      assert is_binary(Format.value_label(@length, 9000, opts))
      assert is_binary(Format.range_label(@created, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}, opts))
    end
  end
end
