if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Browser.AxeTest do
    @moduledoc """
    Automated `axe-core` scans against every dev-playground route (Spec
    005 is the fixture) — the Spec 007 acceptance criterion "axe reports
    zero violations on every playground page, enforced in CI." Runs
    through `a11y_audit` (vendors axe-core, no npm) driven by Wallaby
    against a real, real-HTTP-served `Dev.Endpoint` (see
    `test/support/browser_case.ex`) — axe needs an actually rendered DOM,
    which PhoenixTest's in-process `Phoenix.ConnTest` dispatch can't give
    it. `@moduletag :browser`; excluded from the default `mix test` run.

    One `feature` per fixed playground route (`Dev.Router`) — every route
    except `/records/:type/:id` (dynamic, reached only via palette
    navigation, not a standalone playground page in its own right) —
    written out individually rather than generated from a list: Wallaby's
    `feature/3` re-embeds its message argument's own AST into the
    generated test function (for its screenshot-on-failure path), so a
    `for`-loop-bound variable interpolated into that message isn't
    actually in scope there.
    """

    use Flicker.Test.BrowserCase, async: false

    import Wallaby.Query, only: [css: 1, css: 2]

    feature "/ has zero axe violations", %{session: session} do
      session |> visit("/") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/single-select has zero axe violations", %{session: session} do
      session |> visit("/single-select") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/multi-select has zero axe violations", %{session: session} do
      session |> visit("/multi-select") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/static-provider has zero axe violations", %{session: session} do
      session |> visit("/static-provider") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/themes has zero axe violations", %{session: session} do
      session |> visit("/themes") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/edge-states has zero axe violations", %{session: session} do
      session |> visit("/edge-states") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/keyboard-activation has zero axe violations", %{session: session} do
      session |> visit("/keyboard-activation") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/faceted-search has zero axe violations", %{session: session} do
      session |> visit("/faceted-search") |> A11yAudit.Wallaby.assert_no_violations()
    end

    # The states added by Specs 019/021/022/023 are all *conditional* markup —
    # a dialog, an error region, a counted option list, a Recent group — so
    # scanning the page at rest never sees them. Each is driven into existence
    # before the scan.
    feature "/faceted-search with a facet editor open has zero axe violations", %{session: session} do
      session =
        session
        |> visit("/faceted-search")
        |> fill_in(css("#artist-search-input"), with: "stat")
        |> click(css("[role='option']", text: "status:"))

      # `assert_has/2` is a macro and can't be piped into, so the wait for the
      # conditional markup is its own statement.
      assert_has(session, css("[role='dialog']"))

      A11yAudit.Wallaby.assert_no_violations(session)
    end

    feature "/faceted-search with an invalid facet value has zero axe violations", %{session: session} do
      session =
        session
        |> visit("/faceted-search")
        |> fill_in(css("#artist-search-input"), with: "status:activ ")

      assert_has(session, css("[aria-invalid='true']"))

      A11yAudit.Wallaby.assert_no_violations(session)
    end

    feature "/faceted-search with a committed facet pill has zero axe violations", %{session: session} do
      session =
        session
        |> visit("/faceted-search")
        |> fill_in(css("#artist-search-input"), with: "status:active ")

      assert_has(session, css("[role='listitem']"))

      A11yAudit.Wallaby.assert_no_violations(session)
    end

    feature "/palette (closed) has zero axe violations", %{session: session} do
      session |> visit("/palette") |> A11yAudit.Wallaby.assert_no_violations()
    end

    # The palette's dialog semantics (`role="dialog"`, `aria-modal`, focus
    # trap) are the entire point of Spec 008/007's interest in it — a scan
    # of the closed page tells us nothing about them, so this scans it
    # open too.
    feature "/palette (open) has zero axe violations", %{session: session} do
      session
      |> visit("/palette")
      |> click(css("button", text: "Open command palette"))
      |> assert_has(css("[role=\"dialog\"]", count: 1))
      |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/palette-themed has zero axe violations", %{session: session} do
      session |> visit("/palette-themed") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/cinder-interop has zero axe violations", %{session: session} do
      session |> visit("/cinder-interop") |> A11yAudit.Wallaby.assert_no_violations()
    end

    feature "/windowed-search has zero axe violations", %{session: session} do
      session |> visit("/windowed-search") |> A11yAudit.Wallaby.assert_no_violations()
    end
  end
end
