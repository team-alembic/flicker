defmodule Flicker.RecentValues do
  @moduledoc """
  Recently-used facet values, ranked by frecency
  ([Spec 022](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-022-recently-used-values.md)).

  Most filtering is repetition — the same three workers, the same two
  statuses, retyped every time. Surfacing what someone actually used last, at
  the top of the list, is the cheapest large improvement available to a picker:
  no new interaction to learn, and it collapses a search into one keystroke for
  the values that make up the bulk of real use.

  ## Flicker owns no storage

  Recency is *user data*. Where it lives, how long it's kept, and whether it
  falls under a retention policy are decisions a library shouldn't make on a
  host's behalf — owning a store would mean owning a migration and a GDPR
  question. So a host supplies two functions:

      recent_values: %{
        load: fn facet_key, opts -> [{value, used_at, count}] end,
        record: fn facet_key, value, opts -> :ok end
      }

  `opts` carries `:actor` and `:tenant`, so a host can scope storage per user
  however it likes. Omitting the config disables the feature entirely — no
  group renders and neither function is ever called.

  `Flicker.RecentValues.Ets` ships for the playground and tests, and is
  explicitly not durable.

  ## Recency is a hint, never an authorisation bypass

  A remembered value is only ever a suggestion of what to *offer*. It must be
  resolved through the normal actor-scoped path before display, and anything
  that no longer resolves — deleted, or no longer readable by this actor — is
  **silently** dropped. Not announced, not logged to the user: "you used this
  before but can't see it now" is itself a disclosure.
  """

  require Logger

  @typedoc "A raw usage fact, as a host's `load` returns it."
  @type usage :: {value :: term(), used_at :: DateTime.t(), count :: pos_integer()}

  @typedoc "The host-supplied storage functions."
  @type config :: %{optional(:load) => function(), optional(:record) => function()} | nil

  @default_half_life_days 14
  @default_limit 5

  @doc """
  The default number of recent values shown.

  ## Examples

      iex> Flicker.RecentValues.default_limit()
      5
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Ranks raw usage facts by frecency, most relevant first.

      score = count * 0.5 ** (age_in_days / half_life_days)

  The properties that matter: a value used once today outranks one used twice
  last month, and a value used constantly stays near the top without any single
  use dominating. Ties break on recency.

  `:now` is an argument rather than a call to `DateTime.utc_now/0`, so the decay
  curve is testable at fixed times.

  ## Options

    * `:now` — the reference instant (default: `DateTime.utc_now/0`).
    * `:half_life_days` — decay half-life (default `14`).
    * `:limit` — how many to return (default `5`).

  ## Examples

      iex> now = ~U[2026-07-29 12:00:00Z]
      ...>
      ...> facts = [
      ...>   {:old_favourite, ~U[2026-06-29 12:00:00Z], 2},
      ...>   {:used_today, ~U[2026-07-29 09:00:00Z], 1}
      ...> ]
      ...>
      ...> Flicker.RecentValues.rank(facts, now: now)
      [:used_today, :old_favourite]

      iex> Flicker.RecentValues.rank([], now: ~U[2026-07-29 12:00:00Z])
      []
  """
  @spec rank([usage()], keyword()) :: [term()]
  def rank(facts, opts \\ []) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    half_life = Keyword.get(opts, :half_life_days, @default_half_life_days)
    limit = Keyword.get(opts, :limit, @default_limit)

    facts
    |> Enum.map(fn {value, used_at, count} ->
      {value, score(count, used_at, now, half_life), used_at}
    end)
    |> Enum.sort_by(fn {_value, score, used_at} -> {-score, -DateTime.to_unix(used_at)} end)
    |> Enum.take(limit)
    |> Enum.map(fn {value, _score, _used_at} -> value end)
  end

  defp score(count, used_at, now, half_life) do
    age_days = DateTime.diff(now, used_at, :second) / 86_400

    count * :math.pow(0.5, max(age_days, 0.0) / half_life)
  end

  @doc """
  Loads and ranks a facet's recent values through the host's `load` function.

  Returns `[]` when no config is set, when the facet key isn't known to the
  store, or when `load` misbehaves — this is a nicety, and it must never be the
  reason a picker fails to render.
  """
  @spec load(config(), atom(), keyword()) :: [term()]
  def load(nil, _facet_key, _opts), do: []

  def load(%{load: load}, facet_key, opts) when is_function(load, 2) do
    facet_key
    |> load.(opts)
    |> rank(opts)
  rescue
    exception ->
      Logger.debug("Flicker recent-value load failed: #{inspect(exception)}")
      []
  end

  def load(_config, _facet_key, _opts), do: []

  @doc """
  Records a value as used, through the host's `record` function.

  Fire-and-forget: always returns `:ok`, and a failing `record` is logged at
  debug rather than surfacing. Recording happens on *commit* — a chosen
  suggestion, a confirmed selection, a cleanly-parsed token on dispatch — never
  on hover, focus, keystroke, or a value that failed validation.
  """
  @spec record(config(), atom(), term(), keyword()) :: :ok
  def record(nil, _facet_key, _value, _opts), do: :ok

  def record(%{record: record}, facet_key, value, opts) when is_function(record, 3) do
    record.(facet_key, value, opts)
    :ok
  rescue
    exception ->
      Logger.debug("Flicker recent-value record failed: #{inspect(exception)}")
      :ok
  end

  def record(_config, _facet_key, _value, _opts), do: :ok
end
