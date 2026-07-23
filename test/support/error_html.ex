defmodule Flicker.Test.ErrorHTML do
  @moduledoc """
  A minimal error renderer so a 500 in the test-support endpoint surfaces
  its real reason in test output instead of "no template defined".
  """

  @doc "Renders the failure reason when the endpoint provides one."
  @spec render(String.t(), map()) :: String.t()
  def render(template, %{reason: reason}) do
    "#{template}: #{Exception.format(:error, reason)}"
  end

  def render(template, _assigns), do: template
end
