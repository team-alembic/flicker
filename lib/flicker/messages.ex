defmodule Flicker.Messages do
  @moduledoc """
  The behaviour every user-facing Flicker string routes through (ADR-009).

  Every visible string and every screen-reader announcement the select
  component renders comes from `message/2` — never an inline literal in a
  template. `Flicker.Messages.English` is the complete default
  implementation and doubles as the canonical list of every message key.

  ## Overriding

  A host can override messages globally:

      config :flicker, messages: MyAppWeb.FlickerMessages

  or per-component, via the `messages` attr on `Flicker.select/1`. An
  override module needs only implement the keys it wants to change —
  delegate the rest to `Flicker.Messages.English`:

      defmodule MyAppWeb.FlickerMessages do
        @behaviour Flicker.Messages

        @impl true
        def message(:search_placeholder, _bindings), do: "Rechercher..."
        def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
      end

  Message keys are public API once shipped — renaming one is a breaking
  change.
  """

  @typedoc "A message key. See `Flicker.Messages.English` for the full list."
  @type key :: atom()

  @typedoc "Named values interpolated into a message (e.g. `%{count: 5}`)."
  @type bindings :: map()

  @doc """
  Returns the user-facing string for `key`, interpolating `bindings`.
  """
  @callback message(key(), bindings()) :: String.t()

  @doc """
  Resolves the effective messages module for a component instance.

  Precedence: the per-component `messages` attr override, then
  `config :flicker, :messages`, then `Flicker.Messages.English`.
  """
  @spec resolve(module() | nil) :: module()
  def resolve(component_messages \\ nil)

  def resolve(component_messages) when is_atom(component_messages) and not is_nil(component_messages),
    do: component_messages

  def resolve(nil), do: Application.get_env(:flicker, :messages, Flicker.Messages.English)

  @doc """
  Looks up `key` through the resolved messages module, falling back to
  `Flicker.Messages.English` if the resolved module doesn't implement that
  key — so a partial override module can never crash a render.
  """
  @spec get(module() | nil, key(), bindings()) :: String.t()
  def get(component_messages \\ nil, key, bindings \\ %{}) do
    component_messages
    |> resolve()
    |> apply(:message, [key, bindings])
  rescue
    FunctionClauseError -> Flicker.Messages.English.message(key, bindings)
  end
end
