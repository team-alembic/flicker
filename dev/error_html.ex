defmodule Dev.ErrorHTML do
  @moduledoc """
  A minimal error renderer for the dev playground endpoint (Spec 005), so a
  500 surfaces its real reason instead of "no template defined".
  """

  @doc "Renders `template` — the exception reason, if given, else the bare template name."
  @spec render(String.t(), map()) :: String.t()
  def render(template, %{reason: reason}), do: "#{template}: #{Exception.format(:error, reason)}"
  def render(template, _assigns), do: template
end
