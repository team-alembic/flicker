defmodule Flicker.Test.ConnCase do
  @moduledoc """
  The test case template for PhoenixTest-driven component tests — sets up a
  bare `Plug.Conn` against `Flicker.Test.Endpoint`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ConnTest
      import PhoenixTest
      import Plug.Conn

      @endpoint Flicker.Test.Endpoint
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
