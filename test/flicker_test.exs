defmodule FlickerTest do
  use Flicker.Test.ConnCase, async: true

  doctest Flicker

  describe "validate_mode!/1" do
    test "both field and on_select raises ArgumentError naming the exactly-one rule", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"mode" => "both"})

      assert_raise ArgumentError, ~r/exactly one/, fn ->
        Phoenix.ConnTest.get(conn, "/")
      end
    end
  end
end
