defmodule Flicker.Correction do
  @moduledoc """
  Turning an invalid facet value into an offer to fix it
  ([Spec 023](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-023-inline-value-correction.md)).

  `status:activ` on a closed-set facet is a typo one character from working.
  [ADR-012](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-012-parse-reports-invalid-facet-tokens.md)
  already catches it, keeps it out of the query, and records *why* it failed;
  this module is what turns that record into something actionable.

  ## This is validation-time, not zero-results recovery

  For a closed-set facet the query never ran with `activ` in it — there are no
  zero results to recover from. The correction belongs on the error pill as the
  value is typed, before any dispatch, and every candidate comes from the
  closed set the reason already carries. Suggesting alternatives for a
  `:string` facet is a genuinely different mechanism (fuzzy matching against
  real data, a provider capability) and is deliberately not attempted here.

  ## Two kinds of help

  `candidates/5` guesses: it ranks the facet's own values against what was
  typed. `explain/4` doesn't guess — it states the expected shape, and where a
  *correct* answer exists it offers that answer as a mechanical fix. A reversed
  range and an out-of-bounds number don't need a suggestion, they need a swap
  and a clamp, and offering the answer beats offering advice.

  Nothing here ever rewrites a value on its own. A filter that quietly means
  something other than what is on screen is worse than one that is visibly
  wrong, so a correction is always offered and always accepted explicitly.
  """

  alias Flicker.{Facet, Messages}
  alias Flicker.Facet.{Cast, Range}

  @default_limit 3

  # Jaro similarity below this is noise. Three irrelevant guesses read as a
  # broken component; nothing at all reads as "that isn't a status", which is
  # the more honest message.
  @default_floor 0.75

  @typedoc "A suggested replacement value."
  @type t :: %__MODULE__{value: term(), label: String.t(), score: float()}

  @enforce_keys [:value, :label, :score]
  defstruct [:value, :label, :score]

  @typedoc "A mechanical fix with a known-correct answer, as opposed to a guess."
  @type fix :: nil | {:swap, term()} | {:clamp, term()} | {:replace, term()}

  @doc """
  Ranked replacement candidates for an invalid value, best first.

  Only reasons carrying a closed set produce candidates — in practice
  `:not_in_values`, whose params hold the facet's whole value list. Everything
  else returns `[]`, and the caller falls back to `explain/4`'s statement of
  shape.

  Matching runs against both the value's **key** and its **label**, so `estab`
  finds `:established` even when its label reads "Up and coming", and `coming`
  finds it too. Candidates below the similarity floor are dropped entirely
  rather than padded out to the limit.

  ## Options

    * `:limit` — how many to return (default `3`).
    * `:floor` — minimum similarity, `0.0..1.0` (default `0.75`).

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:active, :inactive])
      ...>
      ...> [top | _] =
      ...>   Flicker.Correction.candidates(facet, "activ", :not_in_values, %{
      ...>     values: [:active, :inactive]
      ...>   })
      ...>
      ...> {top.value, top.label}
      {:active, "active"}

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:active, :inactive])
      ...>
      ...> Flicker.Correction.candidates(facet, "banana", :not_in_values, %{
      ...>   values: [:active, :inactive]
      ...> })
      []

      iex> facet = Flicker.Facet.new(key: :price, type: :integer)
      ...> Flicker.Correction.candidates(facet, "abc", :bad_integer, %{value: "abc"})
      []
  """
  @spec candidates(Facet.t(), String.t(), atom(), map(), keyword()) :: [t()]
  def candidates(facet, raw, reason, params \\ %{}, opts \\ [])

  def candidates(facet, raw, :not_in_values, params, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    floor = Keyword.get(opts, :floor, @default_floor)
    typed = String.downcase(raw)

    params
    |> Map.get(:values, facet.values || [])
    |> Enum.map(&score_value(facet, &1, typed))
    |> Enum.filter(&(&1.score >= floor))
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
  end

  def candidates(_facet, _raw, _reason, _params, _opts), do: []

  defp score_value(facet, value, typed) do
    label = Facet.value_label(facet, value)

    %__MODULE__{
      value: value,
      label: label,
      score:
        max(
          similarity(typed, String.downcase(to_string(value))),
          similarity(typed, String.downcase(label))
        )
    }
  end

  # A prefix or substring match is a stronger signal than raw edit distance —
  # `estab` is unambiguous against `established` even though Jaro alone rates
  # a partial prefix modestly. Scores are capped just under 1.0 so an exact
  # match (which can't happen here, since the value was rejected) stays
  # distinguishable.
  defp similarity(typed, candidate) do
    cond do
      typed == "" -> 0.0
      String.starts_with?(candidate, typed) -> 0.99
      String.contains?(candidate, typed) -> 0.9
      true -> String.jaro_distance(typed, candidate)
    end
  end

  @doc """
  The message for an invalid value, and a mechanical fix when one exists.

  Returns `%{message: String.t(), fix: fix()}`. The message comes from
  `Flicker.Messages`
  ([ADR-009](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-009-messages-module-for-user-facing-text.md)) —
  this module produces no English of its own — and `:fix` is non-nil only where
  the correct answer is computable rather than guessable:

    * `{:swap, range}` for a reversed range: the same endpoints, the right way
      round.
    * `{:clamp, value}` for an out-of-bounds number: the nearest permitted
      value.
    * `{:replace, value}` for anything else with a single obvious answer.

  ## Options

    * `:messages` — a `Flicker.Messages` override module.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> params = %{from: ~D[2026-07-30], to: ~D[2026-07-01]}
      ...> %{fix: {:swap, range}} = Flicker.Correction.explain(facet, :reversed_range, params)
      ...> {range.from, range.to}
      {~D[2026-07-01], ~D[2026-07-30]}

      iex> facet = Flicker.Facet.new(key: :price, type: :integer, bounds: %{min: 0, max: 500})
      ...> Flicker.Correction.explain(facet, :out_of_bounds, %{min: 0, max: 500, value: 900}).fix
      {:clamp, 500}

      iex> facet = Flicker.Facet.new(key: :created, type: :date)
      ...>
      ...> %{message: message, fix: fix} =
      ...>   Flicker.Correction.explain(facet, :bad_date, %{value: "nope"})
      ...>
      ...> {message, fix}
      {"expected a date like 2026-07-01, today, or 7d", nil}
  """
  @spec explain(Facet.t(), atom(), map(), keyword()) :: %{message: String.t(), fix: fix()}
  def explain(facet, reason, params \\ %{}, opts \\ []) do
    %{
      message: Messages.get(Keyword.get(opts, :messages), Cast.message_key(reason), params),
      fix: fix_for(facet, reason, params)
    }
  end

  defp fix_for(_facet, :reversed_range, %{from: from, to: to}) do
    {:swap, %Range{from: to, to: from}}
  end

  defp fix_for(_facet, :out_of_bounds, %{value: value} = params) do
    min = Map.get(params, :min)
    max = Map.get(params, :max)

    cond do
      is_number(min) and value < min -> {:clamp, min}
      is_number(max) and value > max -> {:clamp, max}
      true -> nil
    end
  end

  defp fix_for(_facet, _reason, _params), do: nil

  @doc """
  The canonical token text a chosen candidate or fix should be spliced in as.

  Everything a correction can produce has to serialise back to a token, exactly
  like an editor's output
  ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)) —
  the correction path reuses the same splice as any other suggestion, so it
  must speak the same grammar. Locale-invariant throughout
  ([ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md)).

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:active])
      ...>
      ...> Flicker.Correction.to_token(facet, %Flicker.Correction{
      ...>   value: :active,
      ...>   label: "Active",
      ...>   score: 1.0
      ...> })
      "status:active "

      iex> facet = Flicker.Facet.new(key: :price, type: :integer)
      ...> Flicker.Correction.to_token(facet, {:clamp, 500})
      "price:500 "

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> range = %Flicker.Facet.Range{from: ~D[2026-07-01], to: ~D[2026-07-30]}
      ...> Flicker.Correction.to_token(facet, {:swap, range})
      "created:2026-07-01..2026-07-30 "
  """
  @spec to_token(Facet.t(), t() | fix()) :: String.t() | nil
  def to_token(facet, %__MODULE__{value: value}), do: token(facet, serialise(value))
  def to_token(facet, {:swap, value}), do: token(facet, serialise(value))
  def to_token(facet, {:clamp, value}), do: token(facet, serialise(value))
  def to_token(facet, {:replace, value}), do: token(facet, serialise(value))
  def to_token(_facet, nil), do: nil

  defp token(_facet, nil), do: nil
  defp token(facet, value), do: "#{facet.key}:#{quote_if_needed(value)} "

  defp serialise(%Range{preset: preset}) when not is_nil(preset) do
    case Flicker.Facet.Preset.find_by_id(preset) do
      nil -> nil
      found -> found.token
    end
  end

  defp serialise(%Range{from: nil, to: nil}), do: nil
  defp serialise(%Range{from: from, to: nil}), do: "#{serialise(from)}.."
  defp serialise(%Range{from: nil, to: to}), do: "..#{serialise(to)}"
  defp serialise(%Range{from: from, to: to}), do: "#{serialise(from)}..#{serialise(to)}"
  defp serialise(%Date{} = date), do: Date.to_iso8601(date)
  defp serialise(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp serialise(values) when is_list(values), do: Enum.map_join(values, ",", &serialise/1)
  defp serialise(value), do: to_string(value)

  defp quote_if_needed(value) do
    if String.contains?(value, [" ", "\""]) do
      ~s("#{String.replace(value, "\"", "\\\"")}")
    else
      value
    end
  end
end
