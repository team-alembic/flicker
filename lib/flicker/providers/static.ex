defmodule Flicker.Providers.Static do
  @moduledoc """
  A small in-memory `Flicker.Provider` backed by a fixed list of results.

  This is Flicker's reference pure-Elixir provider: it proves the
  `Flicker.Provider` contract stands alone with no Ash dependency, and it
  doubles as the test double for component tests
  ([Spec 001](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-001-portable-single-select.md)
  onward). It is also the worked example for third parties writing their
  own provider from the docs alone.

  Configure it with `{Flicker.Providers.Static, results: [...]}`:

      results = [
        %Flicker.Result{value: 1, label: "Casey Cassidy", sublabel: "Bass"},
        %Flicker.Result{value: 2, label: "Alex Rivers", sublabel: "Drums"}
      ]

      Flicker.Provider.run_search(
        {Flicker.Providers.Static, results: results},
        %Flicker.Query{text: "cas"}
      )
      #=> {:ok, [%Flicker.Result{value: 1, label: "Casey Cassidy", sublabel: "Bass"}]}

  `search/2` matches `query.text` case-insensitively against `:label` and
  `:sublabel`; a blank query returns the full (optionally `:limit`-ed) list,
  mirroring how a real provider shows a default listing when the picker
  opens with nothing typed yet. `fetch/2` resolves all matching `:value`s in
  one pass, silently omitting any that aren't present in `:results` — the
  same "partial results are normal" behaviour ADR-003 requires of every
  provider.
  """

  @behaviour Flicker.Provider

  alias Flicker.{Query, Result}

  @impl true
  @doc """
  Returns results whose `:label` or `:sublabel` contains `query.text`
  (case-insensitively), up to `opts[:limit]` results (default: no limit).

  A blank `query.text` matches everything, so callers get a listing rather
  than an empty set when the picker opens with no input yet.
  """
  @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def search(%Query{text: text}, opts) do
    results = Keyword.get(opts, :results, [])
    limit = Keyword.get(opts, :limit)

    matched =
      results
      |> Enum.filter(&matches?(&1, text))
      |> maybe_limit(limit)

    {:ok, matched}
  end

  @impl true
  @doc """
  Resolves `values` against `opts[:results]` in one pass, returning only
  the ones present — unresolvable values are simply absent, not an error
  (ADR-003).

  Matches by `to_string/1`, not strict term equality: form-field mode's
  `field.value` always arrives as a string (from params, or a LiveSocket
  reconnect), while a result's `:value` is commonly an integer or atom —
  the same string-normalised comparison `Flicker.Components.Select` itself
  uses everywhere (`reorder_like/2`, `matches_values?/2`, `filter_selected/2`).
  """
  @spec fetch([term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def fetch(values, opts) do
    results = Keyword.get(opts, :results, [])
    wanted = MapSet.new(values, &to_string/1)

    {:ok, Enum.filter(results, &MapSet.member?(wanted, to_string(&1.value)))}
  end

  defp matches?(_result, ""), do: true

  defp matches?(%Result{label: label, sublabel: sublabel}, text) do
    downcased = String.downcase(text)
    contains?(label, downcased) or contains?(sublabel, downcased)
  end

  defp contains?(nil, _text), do: false
  defp contains?(field, text), do: field |> String.downcase() |> String.contains?(text)

  defp maybe_limit(results, nil), do: results
  defp maybe_limit(results, limit), do: Enum.take(results, limit)
end
