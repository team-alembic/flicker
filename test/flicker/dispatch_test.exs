defmodule Flicker.DispatchTest do
  @moduledoc """
  `Flicker.Dispatch` is pure, so the whole of Spec 020's policy is exercised
  here with no LiveView, no provider, and no browser — the same treatment
  `Flicker.CursorContext` gets, and for the same reason.
  """

  use ExUnit.Case, async: true

  alias Flicker.Dispatch
  alias Flicker.Result

  doctest Flicker.Dispatch

  describe "policies/0" do
    test "is the source of truth every other function accepts" do
      for policy <- Dispatch.policies() do
        assert is_boolean(Dispatch.dispatch?(policy, :input, "cas", 0))
        assert is_boolean(Dispatch.pending?(policy, "cas", ""))
      end
    end
  end

  describe "dispatch?/4 — triggers that always dispatch" do
    test "a facet commit dispatches under every policy" do
      for policy <- Dispatch.policies() do
        assert Dispatch.dispatch?(policy, :facet_commit, "", 0),
               "facet commit suppressed under #{policy}"
      end
    end

    test "the initial listing dispatches under every policy" do
      for policy <- Dispatch.policies() do
        assert Dispatch.dispatch?(policy, :initial, "", 0),
               "initial listing suppressed under #{policy}"
      end
    end

    test "a facet commit ignores min_length" do
      for policy <- Dispatch.policies() do
        assert Dispatch.dispatch?(policy, :facet_commit, "c", 5)
      end
    end

    test "the initial listing ignores min_length" do
      for policy <- Dispatch.policies() do
        assert Dispatch.dispatch?(policy, :initial, "", 5)
      end
    end
  end

  describe "dispatch?/4 — policy" do
    test ":debounce and :immediate dispatch on input" do
      assert Dispatch.dispatch?(:debounce, :input, "cas", 0)
      assert Dispatch.dispatch?(:immediate, :input, "cas", 0)
    end

    test ":enter never dispatches on input" do
      refute Dispatch.dispatch?(:enter, :input, "cas", 0)
      refute Dispatch.dispatch?(:enter, :input, "", 0)
    end

    test ":enter dispatches on Enter" do
      assert Dispatch.dispatch?(:enter, :enter, "cas", 0)
    end

    test "Enter dispatches under the dispatching policies too" do
      assert Dispatch.dispatch?(:debounce, :enter, "cas", 0)
      assert Dispatch.dispatch?(:immediate, :enter, "cas", 0)
    end
  end

  describe "dispatch?/4 — min_length" do
    test "withholds a query shorter than min_length" do
      refute Dispatch.dispatch?(:debounce, :input, "c", 2)
      refute Dispatch.dispatch?(:immediate, :input, "c", 2)
    end

    test "allows a query at exactly min_length" do
      assert Dispatch.dispatch?(:debounce, :input, "ca", 2)
    end

    test "blank text always dispatches — it is the listing, not a short search" do
      assert Dispatch.dispatch?(:debounce, :input, "", 5)
      assert Dispatch.dispatch?(:immediate, :input, "", 5)
    end

    test "gates Enter as well, so min_length is not bypassable" do
      refute Dispatch.dispatch?(:enter, :enter, "c", 2)
      assert Dispatch.dispatch?(:enter, :enter, "ca", 2)
    end

    test "counts graphemes, not bytes" do
      refute Dispatch.dispatch?(:debounce, :input, "é", 2)
      assert Dispatch.dispatch?(:debounce, :input, "éé", 2)
    end

    test "min_length: 0 never withholds anything" do
      assert Dispatch.dispatch?(:debounce, :input, "c", 0)
    end
  end

  describe "debounce_attr/2" do
    test ":debounce carries the configured value" do
      assert Dispatch.debounce_attr(:debounce, 150) == 150
      assert Dispatch.debounce_attr(:debounce, 0) == 0
    end

    test ":immediate and :enter omit the attribute" do
      assert Dispatch.debounce_attr(:immediate, 150) == nil
      assert Dispatch.debounce_attr(:enter, 150) == nil
    end
  end

  describe "pending?/3" do
    test "is true under :enter while typed text diverges from what was dispatched" do
      assert Dispatch.pending?(:enter, "casey", "")
      assert Dispatch.pending?(:enter, "casey", "cas")
    end

    test "is false under :enter once they agree" do
      refute Dispatch.pending?(:enter, "casey", "casey")
      refute Dispatch.pending?(:enter, "", "")
    end

    test "is always false under the dispatching policies" do
      refute Dispatch.pending?(:debounce, "casey", "")
      refute Dispatch.pending?(:immediate, "casey", "")
    end
  end

  describe "empty_state/4" do
    @result %Result{value: 1, label: "Casey"}

    test "is :none whenever there are results" do
      assert Dispatch.empty_state(false, "cas", 0, [@result]) == :none
      assert Dispatch.empty_state(true, "cas", 0, [@result]) == :none
      assert Dispatch.empty_state(false, "", 5, [@result]) == :none
    end

    test "is :none while a request is in flight — never 'no results'" do
      assert Dispatch.empty_state(true, "cas", 0, []) == :none
      assert Dispatch.empty_state(true, "", 0, []) == :none
    end

    test "is :below_min_length for text too short to have been dispatched" do
      assert Dispatch.empty_state(false, "c", 2, []) == :below_min_length
    end

    test "is :listing when nothing is typed and the default listing is empty" do
      assert Dispatch.empty_state(false, "", 0, []) == :listing
      assert Dispatch.empty_state(false, "", 2, []) == :listing
    end

    test "is :no_results only for a settled, dispatched, empty search" do
      assert Dispatch.empty_state(false, "cas", 0, []) == :no_results
      assert Dispatch.empty_state(false, "ca", 2, []) == :no_results
    end

    test "never claims :no_results for a query that was never dispatched" do
      for min_length <- 1..5, text <- ["c", "ca", "cas", "case"] do
        state = Dispatch.empty_state(false, text, min_length, [])

        if String.length(text) < min_length do
          assert state == :below_min_length,
                 "claimed #{state} for #{inspect(text)} below min_length #{min_length}"
        end
      end
    end
  end
end
