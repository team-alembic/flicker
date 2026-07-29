defmodule Flicker.Query.Invalid do
  @moduledoc """
  A facet token whose key and operator were both recognised but whose value
  would not cast ([ADR-012](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-012-parse-reports-invalid-facet-tokens.md)).

  Such a token is neither a filter nor free text. It is recorded in
  `Flicker.Query`'s `:invalid` list so a component can render it as an error
  with a real message — `status:activ` names a facet Flicker knows about, with
  an operator it allows, and got the value wrong, which is enough information
  to say precisely what was expected. Degrading it to free text (the fate of
  an *unknown* key) would discard all of that and search for the literal text
  instead, which matches nothing and explains nothing.

  ## Fields

    * `:key` — the facet key that was recognised.
    * `:operator` — the operator that was recognised, already resolved
      through the facet's `:default_op` for the bare `:` form.
    * `:raw` — the value exactly as typed, before any casting.
    * `:token` — the whole `key<op>value` token as typed, for rendering the
      error against what the user actually wrote.
    * `:reason` — a machine-readable atom (`:not_in_values`,
      `:reversed_range`, ...). Rendered through `Flicker.Messages`
      ([ADR-009](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-009-messages-module-for-user-facing-text.md));
      the parser never produces user-facing English.
    * `:params` — the details that reason needs (`%{values: [...]}`,
      `%{min: 0, max: 500}`), also for the message and, in
      [Spec 023](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-023-inline-value-correction.md),
      for computing a correction.
  """

  alias Flicker.Facet

  @typedoc "A recognised facet whose value failed to cast."
  @type t :: %__MODULE__{
          key: atom(),
          operator: Facet.operator(),
          raw: String.t(),
          token: String.t(),
          reason: atom(),
          params: map()
        }

  @enforce_keys [:key, :operator, :raw, :token, :reason]
  defstruct [:key, :operator, :raw, :token, :reason, params: %{}]
end
