defmodule Flicker.SelectTest do
  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers

  defp visit_mode(conn, session_overrides) do
    conn = Plug.Test.init_test_session(conn, session_overrides)
    visit(conn, "/")
  end

  describe "controlled mode" do
    test "renders no form inputs", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "controlled"})
      refute_has(session, "input[type=hidden]")
    end

    test "on_select fires with the selected Flicker.Result", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")

      assert_has(session, "#selection", text: "Casey Cassidy")
    end
  end

  describe "form-field mode" do
    test "hidden input carries the selection into params", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "form"})
        |> type_search("picker-input", "cas")

      session = session |> click_button("Casey Cassidy") |> click_button("Submit")

      assert_has(session, "#submitted", text: ~s("client_id" => "1"))
    end

    test "required error does not fire before the field is engaged", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "form"})
      refute_has(session, "#client-id-error")
    end

    test "value survives providing an initial value (reconnect/edit-form recovery)", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "form", "initial_value" => "2"})
      assert_has(session, "#picker-input[value='Alex Rivers']")
    end
  end

  describe "min_chars" do
    test "no search runs below the configured minimum", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled", "min_chars" => 3})
        |> type_search("picker-input", "ca")

      refute_has(session, "[role='option']")
    end

    test "a search runs once the minimum is met", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled", "min_chars" => 3})
        |> type_search("picker-input", "cas")

      assert_has(session, "[role='option']", text: "Casey Cassidy")
    end

    test "the min_chars hint is shown instead of 'no results' while below the minimum", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled", "min_chars" => 3})
        |> type_search("picker-input", "ca")

      assert_has(session, "li", text: "Type at least 3 characters to search")
      refute_has(session, "li", text: "No results found")
    end
  end

  describe "click/focus outside" do
    test "the listbox closes without selecting", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      assert_has(session, "#picker-listbox")

      html =
        session.view
        |> Phoenix.LiveViewTest.element("#picker")
        |> Phoenix.LiveViewTest.render_hook("close", %{})

      refute html =~ "<ul"
    end

    test "the wrapper binds phx-click-away to close the listbox", %{conn: conn} do
      session = visit_mode(conn, %{"mode" => "controlled"})

      assert_has(session, "#picker[phx-click-away='close']")
    end
  end

  describe "refocusing the input" do
    test "does not discard already-typed text", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      html =
        session.view
        |> Phoenix.LiveViewTest.element("#picker-input")
        |> Phoenix.LiveViewTest.render_focus()

      Phoenix.LiveViewTest.render_async(session.view)

      assert html =~ ~s(value="cas")
      assert_has(session, "[role='option']", text: "Casey Cassidy")
    end
  end

  describe "a stale click" do
    test "a click on a value no longer in @results is a no-op, not a clear", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "controlled"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")
      assert_has(session, "#selection", text: "Casey Cassidy")

      # Simulate results having moved on since the last render (an async
      # response landed, or the facet context flipped) by pushing a "select"
      # for a value that no longer matches anything in @results.
      session.view
      |> Phoenix.LiveViewTest.element("#picker")
      |> Phoenix.LiveViewTest.render_hook("select", %{"value" => "does-not-exist"})

      assert_has(session, "#selection", text: "Casey Cassidy")
    end
  end

  describe "editing the query after selecting" do
    test "clears the stale selection instead of leaving it behind", %{conn: conn} do
      session =
        conn
        |> visit_mode(%{"mode" => "form"})
        |> type_search("picker-input", "cas")

      session = click_button(session, "Casey Cassidy")
      assert_has(session, "#picker-input[value='Casey Cassidy']")

      session = type_search(session, "picker-input", "Casey Cass")

      refute_has(session, "input[name='client_id'][value='1']")
    end
  end
end
