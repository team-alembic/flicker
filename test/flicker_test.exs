defmodule FlickerTest do
  use Flicker.Test.ConnCase, async: true

  doctest Flicker

  describe "validate_mode!/1" do
    test "neither field nor on_select raises ArgumentError", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"mode" => "neither"})

      assert_raise ArgumentError, ~r/requires either/, fn ->
        Phoenix.ConnTest.get(conn, "/")
      end
    end
  end
end
