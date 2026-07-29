defmodule Flicker.CorrectionTest do
  @moduledoc """
  `Flicker.Correction` (Spec 023) — candidates, statements of shape, and the
  mechanical fixes that have a correct answer rather than a guess.
  """

  use ExUnit.Case, async: true

  alias Flicker.{Correction, Facet}
  alias Flicker.Facet.Range

  doctest Flicker.Correction

  @status Facet.new(key: :status, type: :enum, values: [:active, :inactive, :archived])
  @tier Facet.new(
          key: :tier,
          type: :enum,
          values: [:emerging, :established, :legendary],
          value_labels: %{emerging: "Up and coming", established: "Established", legendary: "Legendary"}
        )
  @price Facet.new(key: :price, type: :integer, bounds: %{min: 0, max: 500})
  @created Facet.new(key: :created, type: :date_range)

  defp candidates(facet, raw, opts \\ []) do
    Correction.candidates(facet, raw, :not_in_values, %{values: facet.values}, opts)
  end

  describe "candidates for a closed set" do
    test "a one-character typo finds the intended value" do
      assert [%Correction{value: :active} | _] = candidates(@status, "activ")
    end

    test "a transposition still finds it" do
      assert [%Correction{value: :active} | _] = candidates(@status, "atcive")
    end

    test "matching works against the value key even when the label differs" do
      # `emerg` is unambiguous against `:emerging` whose label is "Up and coming".
      assert [%Correction{value: :emerging} | _] = candidates(@tier, "emerg")
    end

    test "matching works against the label too" do
      assert [%Correction{value: :emerging} | _] = candidates(@tier, "coming")
    end

    test "candidates carry their display label, not the raw atom" do
      assert [%Correction{label: "Up and coming"} | _] = candidates(@tier, "emerg")
    end

    test "results are ordered best-first" do
      scores = @status |> candidates("activ") |> Enum.map(& &1.score)

      assert scores == Enum.sort(scores, :desc)
    end

    test "nothing plausible means no candidates at all, not three bad guesses" do
      assert candidates(@status, "banana") == []
      assert candidates(@status, "zzzzzzzz") == []
    end

    test "an empty typed value offers nothing" do
      assert candidates(@status, "") == []
    end

    test "the limit is respected" do
      facet = Facet.new(key: :x, type: :enum, values: [:aaa1, :aaa2, :aaa3, :aaa4, :aaa5])

      assert length(Correction.candidates(facet, "aaa", :not_in_values, %{values: facet.values}, limit: 2)) == 2
    end

    test "the floor can be lowered to accept weaker matches" do
      assert candidates(@status, "banana") == []
      refute candidates(@status, "banana", floor: 0.0) == []
    end

    test "every candidate is genuinely a member of the closed set" do
      for typed <- ["activ", "arch", "inact", "a", "e"] do
        for %Correction{value: value} <- candidates(@status, typed) do
          assert value in @status.values
        end
      end
    end

    test "reasons without a closed set produce no candidates" do
      for reason <- [:bad_integer, :bad_date, :reversed_range, :out_of_bounds, :incomplete_list, :custom] do
        assert Correction.candidates(@price, "whatever", reason, %{}) == []
      end
    end

    test "falls back to the facet's own values when params carry none" do
      assert [%Correction{value: :active} | _] = Correction.candidates(@status, "activ", :not_in_values, %{})
    end
  end

  describe "explain — statements of shape" do
    test "a bad date says what a date looks like, with real examples" do
      %{message: message, fix: fix} = Correction.explain(@created, :bad_date, %{value: "nope"})

      assert message =~ "2026-07-01"
      assert message =~ "today"
      assert fix == nil
    end

    test "every reason produces a non-empty message" do
      for reason <- Flicker.Facet.Cast.reasons() do
        params = %{values: [:a], min: 0, max: 5, value: 9, from: ~D[2026-07-02], to: ~D[2026-07-01], message: "m"}

        assert %{message: message} = Correction.explain(@price, reason, params)
        assert is_binary(message) and message != "", "#{reason} produced #{inspect(message)}"
      end
    end

    test "a host messages module can override the wording" do
      defmodule TerseMessages do
        @moduledoc false
        @behaviour Flicker.Messages

        @impl true
        def message(:invalid_date, _bindings), do: "bad date"
        def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
      end

      assert %{message: "bad date"} =
               Correction.explain(@created, :bad_date, %{value: "x"}, messages: TerseMessages)
    end
  end

  describe "explain — mechanical fixes" do
    test "a reversed range offers the swap, not advice" do
      params = %{from: ~D[2026-07-30], to: ~D[2026-07-01]}

      assert %{fix: {:swap, %Range{from: ~D[2026-07-01], to: ~D[2026-07-30]}}} =
               Correction.explain(@created, :reversed_range, params)
    end

    test "an over-max value clamps to the max" do
      assert %{fix: {:clamp, 500}} = Correction.explain(@price, :out_of_bounds, %{min: 0, max: 500, value: 900})
    end

    test "an under-min value clamps to the min" do
      assert %{fix: {:clamp, 0}} = Correction.explain(@price, :out_of_bounds, %{min: 0, max: 500, value: -5})
    end

    test "a one-sided bound only clamps on the side that exists" do
      assert %{fix: {:clamp, 10}} = Correction.explain(@price, :out_of_bounds, %{min: 10, max: nil, value: 5})
      assert %{fix: nil} = Correction.explain(@price, :out_of_bounds, %{min: 10, max: nil, value: 50})
    end

    test "reasons with no computable answer offer no fix" do
      for reason <- [:bad_integer, :bad_date, :not_in_values, :incomplete_list, :incomplete_range, :custom] do
        assert %{fix: nil} = Correction.explain(@price, reason, %{values: [:a], value: "x"})
      end
    end
  end

  describe "to_token — corrections speak the same grammar as everything else" do
    test "a candidate serialises to a canonical token" do
      [candidate | _] = candidates(@status, "activ")

      assert Correction.to_token(@status, candidate) == "status:active "
    end

    test "a clamp serialises to a canonical token" do
      assert Correction.to_token(@price, {:clamp, 500}) == "price:500 "
    end

    test "a swapped range serialises to a canonical range literal" do
      fix = {:swap, %Range{from: ~D[2026-07-01], to: ~D[2026-07-30]}}

      assert Correction.to_token(@created, fix) == "created:2026-07-01..2026-07-30 "
    end

    test "a half-open swapped range keeps its open end" do
      assert Correction.to_token(@created, {:swap, %Range{from: ~D[2026-07-01], to: nil}}) ==
               "created:2026-07-01.. "

      assert Correction.to_token(@created, {:swap, %Range{from: nil, to: ~D[2026-07-30]}}) ==
               "created:..2026-07-30 "
    end

    test "a preset range serialises back to its token, not its dates" do
      fix = {:replace, %Range{from: ~D[2026-06-30], to: ~D[2026-07-29], preset: :last_30_days}}

      assert Correction.to_token(@created, fix) == "created:last-30-days "
    end

    test "a list value serialises as a comma literal" do
      facet = Facet.new(key: :status, type: :enum, values: [:active, :archived], multiple?: true)

      assert Correction.to_token(facet, {:replace, [:active, :archived]}) == "status:active,archived "
    end

    test "a value containing a space is quoted" do
      facet = Facet.new(key: :worker, type: :string)

      assert Correction.to_token(facet, {:replace, "Casey Nguyen"}) == ~s(worker:"Casey Nguyen" )
    end

    test "no fix means no token" do
      assert Correction.to_token(@price, nil) == nil
    end

    test "every produced token re-parses to a valid facet" do
      # The whole point: a correction goes through the same splice as any
      # suggestion, so whatever it emits must be grammar the parser accepts.
      cases = [
        {@status, hd(candidates(@status, "activ"))},
        {@price, {:clamp, 500}},
        {@created, {:swap, %Range{from: ~D[2026-07-01], to: ~D[2026-07-30]}}},
        {@created, {:replace, %Range{from: ~D[2026-06-30], to: ~D[2026-07-29], preset: :last_30_days}}}
      ]

      for {facet, correction} <- cases do
        token = Correction.to_token(facet, correction)
        query = Flicker.Query.parse(String.trim(token), [facet])

        assert query.invalid == [], "#{token} re-parsed as invalid: #{inspect(query.invalid)}"
        refute query.facets == [], "#{token} produced no facet"
      end
    end
  end

  describe "totality" do
    test "never raises for any reason/params combination" do
      facets = [@status, @tier, @price, @created]
      reasons = Flicker.Facet.Cast.reasons() ++ [:invented_by_a_host]

      param_sets = [
        %{},
        %{value: "x"},
        %{values: []},
        %{values: [:a, :b]},
        %{min: nil, max: nil, value: 1},
        %{from: ~D[2026-01-01], to: ~D[2026-01-02]},
        %{message: "custom"}
      ]

      for facet <- facets, reason <- reasons, params <- param_sets do
        assert %{message: message} = Correction.explain(facet, reason, params)
        assert is_binary(message)
        assert is_list(Correction.candidates(facet, "typed", reason, params))
      end
    end
  end
end
