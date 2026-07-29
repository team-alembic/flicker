defmodule Flicker.FacetEditorTest do
  @moduledoc """
  The `Flicker.FacetEditor` contract (Spec 019).

  The load-bearing test here is the round-trip property: for every editor and
  every complete value, `serialise` is idempotent through `parse`, **and** the
  text it produced parses to a real filter through `Flicker.Query.parse/2`. That
  second half is what stops an editor drifting from the grammar — the reason
  ADR-011 makes token text an editor's only output.

  Idempotence rather than identity, because the grammar has canonical forms an
  editor's value shape doesn't: a preset parses back resolved, and a
  one-element multi selection parses back bare. Both are pinned explicitly
  below.
  """

  use ExUnit.Case, async: true

  alias Flicker.{Facet, FacetEditor, Query}
  alias Flicker.Facet.Range
  alias Flicker.FacetEditor.{Calendar, Dial, Set, Switch}

  doctest Flicker.FacetEditor
  doctest Flicker.FacetEditor.Calendar
  doctest Flicker.FacetEditor.Dial
  doctest Flicker.FacetEditor.Set
  doctest Flicker.FacetEditor.Switch

  @created Facet.new(key: :created, type: :date_range)
  @single_date Facet.new(key: :on, type: :date)
  @price Facet.new(key: :price, type: :number_range, bounds: %{min: 0, max: 500})
  @status Facet.new(key: :status, type: :enum, values: [:active, :inactive, :archived])
  @multi Facet.new(key: :tags, type: :enum, values: [:a, :b, :c], multiple?: true)
  @verified Facet.new(key: :verified?, type: :boolean)

  # {facet, editor, [complete values]}
  defp cases do
    [
      {@created, Calendar,
       [
         %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]},
         %Range{from: ~D[2026-06-01], to: nil},
         %Range{from: nil, to: ~D[2026-06-30]},
         %Range{from: ~D[2026-07-01], to: ~D[2026-07-01]},
         %Range{preset: :last_30_days},
         %Range{preset: :all_time}
       ]},
      {@single_date, Calendar, [~D[2026-07-01], ~D[2026-01-31]]},
      {@price, Dial,
       [
         %Range{from: 10, to: 50},
         %Range{from: 10, to: nil},
         %Range{from: nil, to: 50},
         %Range{from: 0, to: 500}
       ]},
      {@status, Set, [:active, :archived]},
      {@multi, Set, [[:a], [:a, :b], [:a, :b, :c]]},
      {@verified, Switch, [true, false]}
    ]
  end

  describe "the default type mapping" do
    test "every type with an editor resolves to one" do
      for {facet, editor, _values} <- cases() do
        assert FacetEditor.for_facet(facet) == editor
      end
    end

    test "a facet's own :editor overrides the default" do
      facet = Facet.new(key: :created, type: :date_range, editor: Switch)

      assert FacetEditor.for_facet(facet) == Switch
    end

    test "types without a control get none" do
      for facet <- [
            Facet.new(key: :name, type: :string),
            Facet.new(key: :n, type: :integer),
            Facet.new(key: :f, type: :float)
          ] do
        assert FacetEditor.for_facet(facet) == nil
        refute FacetEditor.editable?(facet)
      end
    end

    test "a bounded numeric facet gets a dial, an unbounded one doesn't" do
      # A slider needs endpoints; inventing them would misrepresent the data.
      assert FacetEditor.for_facet(Facet.new(key: :n, type: :integer, bounds: %{min: 0, max: 9})) == Dial
      assert FacetEditor.for_facet(Facet.new(key: :n, type: :integer)) == nil
    end

    test "only the switch is non-modal" do
      assert FacetEditor.modal?(@created)
      assert FacetEditor.modal?(@price)
      assert FacetEditor.modal?(@status)
      refute FacetEditor.modal?(@verified)
    end
  end

  describe "the round-trip property" do
    test "serialise is idempotent through parse, for every editor and value" do
      # Idempotence rather than structural identity, deliberately: a preset
      # serialises to its id and parses back *resolved*, which is exactly why
      # presets stay relative. Same meaning, same text, different struct.
      for {facet, editor, values} <- cases(), value <- values do
        text = editor.serialise(value, facet)

        assert {:ok, parsed} = editor.parse(text, facet),
               "#{inspect(editor)} could not parse its own #{inspect(text)}"

        assert editor.serialise(parsed, facet) == text,
               "#{inspect(editor)} did not round-trip #{inspect(value)} (via #{inspect(text)})"
      end
    end

    test "the two places structure legitimately changes, and why" do
      # Both are the grammar imposing a canonical form, not an editor bug — and
      # both are why the property is idempotence rather than identity.

      # A preset parses back *resolved*, keeping its id. That is what makes a
      # saved query stay relative.
      preset_text = Calendar.serialise(%Range{preset: :last_30_days}, @created)
      assert {:ok, %Range{preset: :last_30_days, from: %Date{}}} = Calendar.parse(preset_text, @created)

      # A one-element multi selection parses back bare, because a single value
      # with no comma is `:eq` in the grammar, not a one-element `:in`.
      single_text = Set.serialise([:a], @multi)
      assert single_text == "a"
      assert Set.parse(single_text, @multi) == {:ok, :a}

      # ...and both still serialise to the same text they came from.
      assert Calendar.serialise(elem(Calendar.parse(preset_text, @created), 1), @created) == preset_text
      assert Set.serialise(elem(Set.parse(single_text, @multi), 1), @multi) == single_text
    end

    test "every genuinely multi-element or scalar value round-trips identically" do
      identity_cases = [
        {@created, Calendar, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}},
        {@created, Calendar, %Range{from: ~D[2026-06-01], to: nil}},
        {@created, Calendar, %Range{from: nil, to: ~D[2026-06-30]}},
        {@single_date, Calendar, ~D[2026-07-01]},
        {@price, Dial, %Range{from: 10, to: 50}},
        {@price, Dial, %Range{from: 10, to: nil}},
        {@status, Set, :active},
        {@multi, Set, [:a, :b]},
        {@multi, Set, [:a, :b, :c]},
        {@verified, Switch, true},
        {@verified, Switch, false}
      ]

      for {facet, editor, value} <- identity_cases do
        text = editor.serialise(value, facet)

        assert {:ok, ^value} = editor.parse(text, facet),
               "#{inspect(editor)} did not round-trip #{inspect(value)} (via #{inspect(text)})"
      end
    end

    test "a preset round-trips to the same preset, resolved" do
      text = Calendar.serialise(%Range{preset: :last_30_days}, @created)

      assert {:ok, %Range{preset: :last_30_days, from: %Date{}, to: %Date{}}} = Calendar.parse(text, @created)
    end

    test "every serialised value parses to a real filter through the parser" do
      # The half that stops an editor drifting from the grammar.
      for {facet, editor, values} <- cases(), value <- values do
        token = FacetEditor.to_token(editor, value, facet)

        refute is_nil(token), "#{inspect(editor)} produced no token for #{inspect(value)}"

        query = Query.parse(String.trim(token), [facet])

        assert query.invalid == [],
               "#{token} reported invalid: #{inspect(query.invalid)}"

        refute query.facets == [], "#{token} produced no facet"
      end
    end

    test "a preset commits its id, not the dates it resolved to" do
      token = FacetEditor.to_token(Calendar, %Range{preset: :last_30_days}, @created)

      assert token == "created:last-30-days "
    end

    test "parsing a token from the parser's own output also works" do
      # The reverse direction: reopening a committed facet.
      query = Query.parse("created:2026-06-01..2026-06-30", [@created])
      [{_key, _op, value}] = query.facets

      assert {:ok, ^value} = Calendar.parse(Calendar.serialise(value, @created), @created)
    end
  end

  describe "complete?/2 gates commits" do
    test "an incomplete value produces no token at all" do
      incomplete = [
        {@created, Calendar, %Range{}},
        {@price, Dial, %Range{}},
        {@multi, Set, []},
        {@multi, Set, nil},
        {@verified, Switch, nil}
      ]

      for {facet, editor, value} <- incomplete do
        refute editor.complete?(value, facet), "#{inspect(editor)} called #{inspect(value)} complete"
        assert FacetEditor.to_token(editor, value, facet) == nil
      end
    end

    test "a half-open range is committable, but an empty one is not" do
      # `2026-07-01..` is a real filter ("from then on"), so it commits. Only a
      # range with neither endpoint is a non-value — which is what the footer's
      # "pick an end date" prompt is about while a *draft* start is pending.
      assert Calendar.complete?(%Range{from: ~D[2026-07-01], to: nil}, @created)
      assert Calendar.complete?(%Range{from: nil, to: ~D[2026-07-01]}, @created)
      refute Calendar.complete?(%Range{from: nil, to: nil}, @created)
    end
  end

  describe "draft_label/3" do
    test "a half-made range says so in words" do
      label = Calendar.draft_label(%Range{from: ~D[2026-06-18], to: nil}, @created, [])

      assert label =~ "pick an end date"
    end

    test "a complete value has no draft label" do
      assert Calendar.draft_label(%Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}, @created, []) == nil
    end
  end

  describe "Calendar grid maths" do
    test "a month grid is always whole weeks" do
      for month <- [~D[2026-01-01], ~D[2026-02-01], ~D[2026-07-01], ~D[2024-02-01]], week_start <- [1, 7] do
        grid = Calendar.month_grid(month, week_start)

        assert rem(length(grid), 7) == 0, "#{month} / #{week_start} was not whole weeks"
      end
    end

    test "every day of the month appears exactly once" do
      grid = Calendar.month_grid(~D[2026-07-01], 1)
      days = grid |> Enum.reject(&is_nil/1) |> Enum.map(& &1.day)

      assert days == Enum.to_list(1..31)
    end

    test "the first real day lands under its own weekday column" do
      for week_start <- [1, 7] do
        grid = Calendar.month_grid(~D[2026-07-01], week_start)
        index = Enum.find_index(grid, &(&1 == ~D[2026-07-01]))

        assert Integer.mod(Date.day_of_week(~D[2026-07-01]) - week_start, 7) == index
      end
    end

    test "weekday initials rotate with the locale's first day" do
      assert Calendar.weekday_initials(1) == ~w(M T W T F S S)
      assert hd(Calendar.weekday_initials(7)) == "S"
      assert length(Calendar.weekday_initials(7)) == 7
    end

    test "the hover band covers the days between, in either direction" do
      assert Calendar.in_band?(~D[2026-07-05], ~D[2026-07-01], ~D[2026-07-10])
      assert Calendar.in_band?(~D[2026-07-05], ~D[2026-07-10], ~D[2026-07-01])
      refute Calendar.in_band?(~D[2026-07-20], ~D[2026-07-01], ~D[2026-07-10])
    end

    test "no band without both ends" do
      refute Calendar.in_band?(~D[2026-07-05], nil, ~D[2026-07-10])
      refute Calendar.in_band?(~D[2026-07-05], ~D[2026-07-01], nil)
    end
  end

  describe "Dial maths" do
    test "thumb positions map bounds onto a percentage" do
      assert Dial.thumb_percent(0, %{min: 0, max: 100}) == 0.0
      assert Dial.thumb_percent(50, %{min: 0, max: 100}) == 50.0
      assert Dial.thumb_percent(100, %{min: 0, max: 100}) == 100.0
    end

    test "out-of-range values clamp rather than overflow the track" do
      assert Dial.thumb_percent(-50, %{min: 0, max: 100}) == 0.0
      assert Dial.thumb_percent(150, %{min: 0, max: 100}) == 100.0
    end

    test "an open endpoint or an unbounded facet has no position" do
      assert Dial.thumb_percent(nil, %{min: 0, max: 100}) == nil
      assert Dial.thumb_percent(50, nil) == nil
      assert Dial.thumb_percent(50, %{min: 0}) == nil
    end

    test "thumbs clamp instead of crossing, and may meet" do
      range = %Range{from: 10, to: 50}

      assert Dial.clamp_endpoint(:from, 80, range) == 50
      assert Dial.clamp_endpoint(:to, 5, range) == 10
      assert Dial.clamp_endpoint(:from, 50, range) == 50
      assert Dial.clamp_endpoint(:to, 10, range) == 10
    end

    test "an open opposite endpoint imposes no clamp" do
      assert Dial.clamp_endpoint(:from, 999, %Range{to: nil}) == 999
      assert Dial.clamp_endpoint(:to, -999, %Range{from: nil}) == -999
    end
  end

  describe "Set serialisation" do
    test "a value containing a comma or space is quoted so the list literal survives" do
      facet = Facet.new(key: :worker, type: :string)

      assert Set.serialise("Nguyen, Casey", facet) == ~s("Nguyen, Casey")
      assert Set.serialise("Casey Nguyen", facet) == ~s("Casey Nguyen")
    end

    test "a multi selection is a comma literal" do
      assert Set.serialise([:a, :b, :c], @multi) == "a,b,c"
    end
  end
end
