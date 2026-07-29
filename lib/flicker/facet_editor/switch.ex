defmodule Flicker.FacetEditor.Switch do
  @moduledoc """
  The boolean editor ([Spec 019](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-019-facet-editors.md)) —
  and the one editor with no pop-out.

  A flick is a complete value, so there is nothing for a modal surface to
  protect: it commits on toggle, inline
  ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)).
  Atomic commit still applies — this is the degenerate case where "atomic" and
  "one interaction" coincide.

  "Filtered false" and "not filtered at all" stay distinct: the switch expresses
  the first, and the pill's remove control the second. That is why there is no
  third position here.
  """

  @behaviour Flicker.FacetEditor

  use Phoenix.Component

  alias Flicker.Facet

  @impl true
  def modal?, do: false

  @impl true
  @doc """
  `"true"` or `"false"` — the same literals the grammar accepts.

  ## Examples

      iex> Flicker.FacetEditor.Switch.serialise(true, %Flicker.Facet{key: :verified?})
      "true"
  """
  @spec serialise(boolean(), Facet.t()) :: String.t()
  def serialise(value, _facet), do: to_string(value)

  @impl true
  @doc """
  Parses either literal, case-insensitively — matching the parser rather than
  being stricter than it.

  ## Examples

      iex> Flicker.FacetEditor.Switch.parse("TRUE", %Flicker.Facet{key: :verified?})
      {:ok, true}

      iex> Flicker.FacetEditor.Switch.parse("maybe", %Flicker.Facet{key: :verified?})
      :error
  """
  @spec parse(String.t(), Facet.t()) :: {:ok, boolean()} | :error
  def parse(text, _facet) do
    case String.downcase(text) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> :error
    end
  end

  @impl true
  @doc """
  Any boolean is complete; `nil` (nothing chosen yet) is not.

  ## Examples

      iex> Flicker.FacetEditor.Switch.complete?(false, %Flicker.Facet{key: :v})
      true

      iex> Flicker.FacetEditor.Switch.complete?(nil, %Flicker.Facet{key: :v})
      false
  """
  @spec complete?(term(), Facet.t()) :: boolean()
  def complete?(value, _facet), do: is_boolean(value)

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@value == true)}
      aria-label={@labels.values}
      class={[@theme.switch, @value == true && @theme.switch_on]}
      disabled={@disabled}
      phx-click="facet_editor_commit"
      phx-value-insert={@toggled_token}
      phx-target={@target}
    >
      <span class={@theme.switch_thumb} aria-hidden="true"></span>
    </button>
    """
  end
end
