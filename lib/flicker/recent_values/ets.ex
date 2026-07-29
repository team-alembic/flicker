defmodule Flicker.RecentValues.Ets do
  @moduledoc """
  A **dev/test-only** in-memory `Flicker.RecentValues` store
  ([Spec 022](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-022-recently-used-values.md)).

  Not durable, not shared across nodes, and gone on restart. It exists so the
  playground can demonstrate the `Recent` group and so tests have a real store
  to drive, **not** as something to point a production app at — see
  `Flicker.RecentValues` for why Flicker deliberately owns no persistence.

  ## Usage

      Flicker.RecentValues.Ets.start()

      <Flicker.search
        recent_values={Flicker.RecentValues.Ets.config()}
        ...
      />

  Entries are keyed by `{scope, facet_key, value}`, where `scope` is derived
  from the `:actor` in opts — so two actors in the same dev session don't see
  each other's history, mirroring what a real host's per-user storage would do.
  """

  @table __MODULE__

  @doc """
  Creates the backing table if it doesn't exist. Idempotent.
  """
  @spec start() :: :ok
  def start do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _reference -> @table
    end

    :ok
  end

  @doc """
  The `recent_values` config map to hand to a component.
  """
  @spec config() :: %{load: function(), record: function()}
  def config do
    %{load: &load/2, record: &record/3}
  end

  @doc """
  Every recorded usage for `facet_key` in the caller's scope, as
  `{value, used_at, count}` triples.

  Returns facts, not an opinion — `Flicker.RecentValues.rank/2` does the
  ordering, so ranking stays one testable function rather than something each
  store reimplements.
  """
  @spec load(atom(), keyword()) :: [Flicker.RecentValues.usage()]
  def load(facet_key, opts) do
    start()
    scope = scope(opts)

    @table
    |> :ets.match_object({{scope, facet_key, :_}, :_, :_})
    |> Enum.map(fn {{_scope, _key, value}, used_at, count} -> {value, used_at, count} end)
  end

  @doc """
  Records one use of `value`, bumping its count and its timestamp.
  """
  @spec record(atom(), term(), keyword()) :: :ok
  def record(facet_key, value, opts) do
    start()
    key = {scope(opts), facet_key, value}
    now = Keyword.get(opts, :now) || DateTime.utc_now()

    count =
      case :ets.lookup(@table, key) do
        [{^key, _used_at, count}] -> count + 1
        [] -> 1
      end

    :ets.insert(@table, {key, now, count})

    :ok
  end

  @doc """
  Clears everything. Test support.
  """
  @spec clear() :: :ok
  def clear do
    start()
    :ets.delete_all_objects(@table)

    :ok
  end

  # A stable term per actor. Two actors in one dev session must not share
  # history — the same separation a host's per-user storage would give.
  defp scope(opts) do
    case Keyword.get(opts, :actor) do
      nil -> :anonymous
      actor -> :erlang.phash2(actor)
    end
  end
end
