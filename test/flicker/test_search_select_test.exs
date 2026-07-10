defmodule Flicker.TestSearchSelectTest do
  @moduledoc """
  Exercises the published `Flicker.Test.search_select/3` helper end-to-end
  against the same host fixture `Flicker.SelectTest` drives directly — this
  is the "a consumer test can drive selection with `search_select/3` alone"
  acceptance criterion (Spec 001).
  """

  use Flicker.Test.ConnCase, async: true

  defp visit_mode(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/")
  end

  test "controlled mode: opens, filters, and selects an option", %{conn: conn} do
    session =
      conn
      |> visit_mode(%{"mode" => "controlled"})
      |> Flicker.Test.search_select("Search...", "Casey Cassidy")

    assert_has(session, "#selection", text: "Casey Cassidy")
  end

  test "form-field mode: the hidden input carries the selection into submitted params", %{conn: conn} do
    session =
      conn
      |> visit_mode(%{"mode" => "form"})
      |> Flicker.Test.search_select("Search...", "Casey Cassidy")

    session = click_button(session, "Submit")

    assert_has(session, "#submitted", text: ~s("client_id" => "1"))
  end

  test "re-opens by the currently selected label to change the selection", %{conn: conn} do
    session =
      conn
      |> visit_mode(%{"mode" => "controlled"})
      |> Flicker.Test.search_select("Search...", "Casey Cassidy")

    assert_has(session, "#selection", text: "Casey Cassidy")

    session = Flicker.Test.search_select(session, "Casey Cassidy", "Alex Rivers")

    assert_has(session, "#selection", text: "Alex Rivers")
  end
end
