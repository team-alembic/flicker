defmodule Flicker.Facet.Range do
  @moduledoc """
  The cast value of every range-typed facet ([Spec 018](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-018-rich-facet-types.md)) —
  `created:2026-06-01..2026-06-30`, `price:10..50`, `created:last-30-days`.

  ## Fields

    * `:from` — the lower endpoint, cast per the facet's `:scalar`. `nil` is
      an **open** lower bound (`..2026-06-30` means "up to and including
      June 30th, from whenever").
    * `:to` — the upper endpoint, same casting. `nil` is an open upper bound.
    * `:preset` — the id of the semantic preset this range came from
      (`:last_30_days`), or `nil` for an explicitly typed range.

  ## Why `:preset` is carried

  A resolved range and the preset that produced it are not the same fact. A
  pill rendering `%Range{from: ~D[2026-06-29], to: ~D[2026-07-28]}` can only
  say "Jun 29 – Jul 28"; one that also knows `preset: :last_30_days` can say
  **"Last 30 days"**, which is what the user actually chose. It is also why
  presets serialise back to their token rather than their endpoints
  ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)):
  a saved or shared query stays relative instead of freezing to the day it
  was made.

  Both endpoints are `nil` only for the `all-time` preset, which is a
  deliberate no-op filter rather than an empty one — see `unbounded?/1`.
  """

  @typedoc "A cast range value."
  @type t :: %__MODULE__{
          from: term() | nil,
          to: term() | nil,
          preset: atom() | nil
        }

  defstruct from: nil, to: nil, preset: nil

  @doc """
  Whether this range constrains nothing — both endpoints open.

  `Flicker.Query.to_filter/2` contributes no clause at all for such a range,
  which is what makes `all-time` mean "don't filter by date" rather than
  "match nothing".

  ## Examples

      iex> Flicker.Facet.Range.unbounded?(%Flicker.Facet.Range{})
      true

      iex> Flicker.Facet.Range.unbounded?(%Flicker.Facet.Range{preset: :all_time})
      true

      iex> Flicker.Facet.Range.unbounded?(%Flicker.Facet.Range{from: 10})
      false
  """
  @spec unbounded?(t()) :: boolean()
  def unbounded?(%__MODULE__{from: nil, to: nil}), do: true
  def unbounded?(%__MODULE__{}), do: false

  @doc """
  Whether both endpoints are set and equal — a single-day date range, or a
  numeric range collapsed to one value.

  ## Examples

      iex> Flicker.Facet.Range.single?(%Flicker.Facet.Range{
      ...>   from: ~D[2026-07-01],
      ...>   to: ~D[2026-07-01]
      ...> })
      true

      iex> Flicker.Facet.Range.single?(%Flicker.Facet.Range{from: 10, to: 50})
      false

      iex> Flicker.Facet.Range.single?(%Flicker.Facet.Range{from: 10})
      false
  """
  @spec single?(t()) :: boolean()
  def single?(%__MODULE__{from: nil}), do: false
  def single?(%__MODULE__{to: nil}), do: false
  def single?(%__MODULE__{from: same, to: same}), do: true
  def single?(%__MODULE__{}), do: false
end
