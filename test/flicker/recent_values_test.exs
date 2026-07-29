defmodule Flicker.RecentValuesTest do
  @moduledoc """
  Frecency ranking and the host-storage boundary (Spec 022). Every case fixes
  `:now`, since `rank/2` takes the reference instant as an argument precisely so
  the decay curve is pinnable.
  """

  use ExUnit.Case, async: true

  alias Flicker.RecentValues

  doctest Flicker.RecentValues

  @now ~U[2026-07-29 12:00:00Z]

  defp days_ago(days), do: DateTime.add(@now, -days * 86_400, :second)

  defp rank(facts, opts \\ []), do: RecentValues.rank(facts, Keyword.put_new(opts, :now, @now))

  describe "rank/2 — the properties that matter" do
    test "a value used once today outranks one used twice a month ago" do
      facts = [{:old, days_ago(30), 2}, {:today, days_ago(0), 1}]

      assert rank(facts) == [:today, :old]
    end

    test "a constantly-used value stays near the top without one use dominating" do
      facts = [
        {:constant, days_ago(1), 20},
        {:once_today, days_ago(0), 1}
      ]

      assert rank(facts) == [:constant, :once_today]
    end

    test "at equal age, higher count wins" do
      facts = [{:less, days_ago(3), 1}, {:more, days_ago(3), 5}]

      assert rank(facts) == [:more, :less]
    end

    test "at equal count, more recent wins" do
      facts = [{:older, days_ago(10), 3}, {:newer, days_ago(1), 3}]

      assert rank(facts) == [:newer, :older]
    end

    test "exactly one half-life halves the contribution" do
      # 2 uses a half-life ago should tie 1 use now, and the tie breaks on
      # recency.
      facts = [{:decayed, days_ago(14), 2}, {:fresh, days_ago(0), 1}]

      assert rank(facts, half_life_days: 14) == [:fresh, :decayed]
    end

    test "a shorter half-life punishes age harder" do
      facts = [{:old, days_ago(14), 4}, {:new, days_ago(0), 1}]

      assert rank(facts, half_life_days: 100) == [:old, :new]
      assert rank(facts, half_life_days: 2) == [:new, :old]
    end

    test "is deterministic and stable for identical facts" do
      facts = [{:a, days_ago(1), 1}, {:b, days_ago(1), 1}]

      assert rank(facts) == rank(facts)
    end

    test "caps at the limit" do
      facts = for n <- 1..10, do: {n, days_ago(n), 1}

      assert length(rank(facts)) == RecentValues.default_limit()
      assert length(rank(facts, limit: 2)) == 2
    end

    test "handles an empty list and a future timestamp without raising" do
      assert rank([]) == []
      assert rank([{:future, DateTime.add(@now, 86_400, :second), 1}]) == [:future]
    end
  end

  describe "the storage boundary" do
    test "no config means no calls and no values" do
      assert RecentValues.load(nil, :status, []) == []
      assert RecentValues.record(nil, :status, :active, []) == :ok
    end

    test "a malformed config is inert rather than raising" do
      assert RecentValues.load(%{}, :status, []) == []
      assert RecentValues.record(%{}, :status, :active, []) == :ok
    end

    test "load ranks whatever the host returns — order in is irrelevant" do
      config = %{
        load: fn :status, _opts -> [{:old, days_ago(30), 2}, {:today, days_ago(0), 1}] end,
        record: fn _key, _value, _opts -> :ok end
      }

      assert RecentValues.load(config, :status, now: @now) == [:today, :old]
    end

    test "a raising load is swallowed — recency must never break a render" do
      config = %{load: fn _key, _opts -> raise "boom" end, record: fn _k, _v, _o -> :ok end}

      assert RecentValues.load(config, :status, []) == []
    end

    test "a raising record is swallowed and still returns :ok" do
      config = %{load: fn _k, _o -> [] end, record: fn _key, _value, _opts -> raise "boom" end}

      assert RecentValues.record(config, :status, :active, []) == :ok
    end

    test "opts reach the host functions, so storage can be actor-scoped" do
      test_pid = self()

      config = %{
        load: fn key, opts ->
          send(test_pid, {:loaded, key, Keyword.get(opts, :actor)})
          []
        end,
        record: fn key, value, opts ->
          send(test_pid, {:recorded, key, value, Keyword.get(opts, :actor)})
          :ok
        end
      }

      RecentValues.load(config, :status, actor: %{id: 1})
      RecentValues.record(config, :status, :active, actor: %{id: 1})

      assert_received {:loaded, :status, %{id: 1}}
      assert_received {:recorded, :status, :active, %{id: 1}}
    end
  end

  describe "the ETS dev store" do
    setup do
      Flicker.RecentValues.Ets.clear()
      :ok
    end

    test "records and loads usage facts" do
      Flicker.RecentValues.Ets.record(:status, :active, now: @now)

      assert [{:active, _used_at, 1}] = Flicker.RecentValues.Ets.load(:status, [])
    end

    test "repeated uses accumulate a count" do
      for _ <- 1..3, do: Flicker.RecentValues.Ets.record(:status, :active, now: @now)

      assert [{:active, _used_at, 3}] = Flicker.RecentValues.Ets.load(:status, [])
    end

    test "keeps facets separate" do
      Flicker.RecentValues.Ets.record(:status, :active, [])
      Flicker.RecentValues.Ets.record(:tier, :legendary, [])

      assert [{:active, _, _}] = Flicker.RecentValues.Ets.load(:status, [])
      assert [{:legendary, _, _}] = Flicker.RecentValues.Ets.load(:tier, [])
    end

    test "keeps actors separate — one dev session's actors don't share history" do
      Flicker.RecentValues.Ets.record(:status, :active, actor: %{id: 1})

      assert [{:active, _, _}] = Flicker.RecentValues.Ets.load(:status, actor: %{id: 1})
      assert Flicker.RecentValues.Ets.load(:status, actor: %{id: 2}) == []
    end

    test "its config plugs straight into load/record" do
      config = Flicker.RecentValues.Ets.config()

      RecentValues.record(config, :status, :active, [])

      assert RecentValues.load(config, :status, now: @now) == [:active]
    end
  end
end
