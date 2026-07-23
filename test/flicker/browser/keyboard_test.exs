if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Browser.KeyboardTest do
    @moduledoc """
    Browser-driven coverage (Spec 007) of the client-side keyboard
    behaviour ExUnit/PhoenixTest can't reach — the colocated `.Nav`/
    `.Palette` hooks' actual DOM/keyboard-event handling, not the server
    events they push. Test names reference the exact
    [Spec 001 keyboard map](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-001-portable-single-select.md#keyboard-interaction--the-full-map)
    row (or the Spec 006/008/010 equivalent) each one exercises, so
    coverage against that map is auditable.

    Runs against the dev playground (`/single-select`, `/palette`,
    `/windowed-search`) via Wallaby — see `test/support/browser_case.ex`
    for how `Dev.Endpoint` is booted for real over HTTP.
    """

    use Flicker.Test.BrowserCase, async: false

    import Wallaby.Query, only: [css: 1, css: 2]

    @artist_input css("#artist-form-select-input")
    @artist_options_any css("#artist-form-select-listbox [role='option']", count: :any)

    defp js_value(session, script) do
      Wallaby.Browser.execute_script(session, script, [], fn value -> Process.put(:flicker_js_value, value) end)
      Process.get(:flicker_js_value)
    end

    defp active_descendant(session) do
      js_value(session, """
      var el = document.getElementById('artist-form-select-input')
      return el ? el.getAttribute('aria-activedescendant') : null
      """)
    end

    defp active_element_identity(session) do
      js_value(session, """
      var el = document.activeElement
      return el ? (el.id || el.getAttribute('aria-label') || el.tagName) : null
      """)
    end

    # Case-insensitive — mirrors the fix in `Flicker.Components.Select`/
    # `Flicker.Components.Palette`'s own `flickerIsMac`/`flickerPaletteIsMac`
    # (BUG: Chromium's `userAgentData.platform` reports "macOS", lowercase
    # `m`, which a case-sensitive `/Mac/` test never matches — a
    # case-sensitive helper here would send `:control` on real Mac Chrome
    # and never actually exercise the Cmd+K path the fix is for).
    defp mac?(session) do
      js_value(session, """
      return /mac|iphone|ipad/i.test(navigator.userAgentData?.platform || navigator.platform || '')
      """)
    end

    defp open_chord_modifier(session), do: if(mac?(session), do: :command, else: :control)

    # WebDriver modifier keys are *toggles*: `send_keys([:command, "k"])`
    # leaves the modifier held down, poisoning every later keystroke (and
    # a second identical call releases it *before* "k", sending a bare
    # keypress instead of the chord). Press, chord, release.
    defp send_chord(session, modifier, key), do: send_keys(session, [modifier, key, modifier])

    # A page-wide chord (`mod+k`) or a keydown listener registered in a
    # hook's `mounted()` only exists once the LiveSocket has actually
    # joined — sending it the instant `visit/2` returns races that join
    # (the static HTML is already there; the socket isn't yet), flaking the
    # chord/focus-trap features below. `phx-connected` is the class
    # `Phoenix.LiveView`'s own JS adds to the view's root once joined
    # (`PHX_CONNECTED_CLASS`), so waiting for it is the same signal the
    # framework itself uses for connected-only CSS.
    defp wait_for_connected(session), do: assert_has(session, css("[data-phx-main].phx-connected"))

    # | open | ArrowDown / ArrowUp | move active option down/up; no wrap — stops at last/first |
    feature "spec-001: ArrowDown/ArrowUp move the active option with no wrap at either end",
            %{session: session} do
      session = session |> visit("/single-select") |> click(@artist_input)

      options = find(session, @artist_options_any)
      option_count = length(options)
      assert option_count > 0

      first_id = Wallaby.Element.attr(List.first(options), "id")
      last_id = Wallaby.Element.attr(List.last(options), "id")

      # ArrowDown from no highlight lands on the first option, and repeating
      # it past the last option stops there instead of wrapping to the first.
      session = send_keys(session, List.duplicate(:down_arrow, option_count + 3))
      assert active_descendant(session) == last_id

      # ArrowUp back past the first option stops there instead of wrapping
      # to the last.
      session = send_keys(session, List.duplicate(:up_arrow, option_count + 3))
      assert active_descendant(session) == first_id
    end

    # | open, results updated | — | active option resets to none... | plus
    # the `aria-activedescendant` wiring itself (the input's DOM focus never
    # moves — only this attribute tracks the highlighted option).
    feature "spec-001: aria-activedescendant tracks the active option, and focus never leaves the input",
            %{session: session} do
      session = session |> visit("/single-select") |> click(@artist_input)
      options = find(session, @artist_options_any)
      refute Enum.empty?(options)

      refute active_descendant(session)
      assert active_element_identity(session) == "artist-form-select-input"

      session = send_keys(session, [:down_arrow])
      first_id = Wallaby.Element.attr(List.first(options), "id")
      assert active_descendant(session) == first_id
      # Highlight moves via aria-activedescendant, never DOM focus.
      assert active_element_identity(session) == "artist-form-select-input"
    end

    # | open | Enter | select the active option, close, focus stays in
    # input; never submits the surrounding form while open |
    feature "spec-001: Enter selects the highlighted option and never submits the surrounding form",
            %{session: session} do
      session = visit(session, "/single-select")
      url_before = current_url(session)

      session = click(session, @artist_input)
      assert_has(session, css("#artist-form-select-listbox [role='option']", minimum: 1))

      session = session |> send_keys([:down_arrow]) |> send_keys([:enter])

      # `refute_has` doesn't poll the way `assert_has` does — if the
      # listbox is still present at the instant it's called, it fails
      # immediately rather than giving the still-in-flight close a moment
      # to land. Waiting for the settled `aria-expanded="false"` first
      # (which *does* poll) makes the following `refute_has` a same-instant
      # confirmation instead of a race.
      assert_has(session, css("#artist-form-select-input[aria-expanded='false']"))

      # A native form submit (no `phx-submit` on `<.form for={@form}>`)
      # would navigate the page — the tell-tale sign Enter was NOT
      # intercepted. Since it must be, the URL stays exactly where it was.
      assert current_url(session) == url_before
      refute_has(session, css("#artist-form-select-listbox"))
      assert Wallaby.Browser.attr(session, @artist_input, "value") != ""
      # Focus stays in the input after selecting.
      assert active_element_identity(session) == "artist-form-select-input"
    end

    # A mouse click on an option selects it and the listbox stays closed —
    # it must not flicker back open. `mousedown` on the option would
    # otherwise blur the input, and the selection's programmatic refocus
    # would fire `phx-focus` and reopen it; the `.Nav` hook preventDefaults
    # the option mousedown to keep focus on the input (same end state as the
    # Enter path, which never loses focus).
    feature "spec-001: clicking an option selects it and the listbox stays closed",
            %{session: session} do
      session = visit(session, "/single-select")
      session = click(session, @artist_input)
      assert_has(session, css("#artist-form-select-listbox [role='option']", minimum: 1))

      session = click(session, css("#artist-form-select-listbox [role='option']", minimum: 1, at: 0))

      assert_has(session, css("#artist-form-select-input[aria-expanded='false']"))
      refute_has(session, css("#artist-form-select-listbox"))
      assert Wallaby.Browser.attr(session, @artist_input, "value") != ""
    end

    # | open | Escape | close the listbox, keep input text; a second
    # Escape (closed, text present) clears the input |
    feature "spec-001: two-stage Escape — first closes keeping text, second clears it",
            %{session: session} do
      session = session |> visit("/single-select") |> click(@artist_input)
      assert_has(session, css("#artist-form-select-listbox [role='option']", minimum: 1))

      session = fill_in(session, @artist_input, with: "cas")
      # Wait for the narrowed results to land before Escape — an Escape
      # racing the still-debounced "cas" query would close a listbox that
      # query is about to legitimately reopen.
      assert_has(session, css("#artist-form-select-listbox [role='option']", text: "Cassidy", minimum: 1))

      session = send_keys(session, [:escape])
      assert_has(session, css("#artist-form-select-input[aria-expanded='false']"))
      refute_has(session, css("#artist-form-select-listbox"))
      assert Wallaby.Browser.attr(session, @artist_input, "value") == "cas"

      session = send_keys(session, [:escape])
      assert_has(session, css("#artist-form-select-input[value='']"))
    end

    # | open | Tab | close without selecting; focus moves per natural tab
    # order |
    feature "spec-001: Tab closes the listbox without selecting", %{session: session} do
      session = session |> visit("/single-select") |> click(@artist_input)
      assert_has(session, css("#artist-form-select-listbox [role='option']", minimum: 1))

      session = send_keys(session, [:tab])
      assert_has(session, css("#artist-form-select-input[aria-expanded='false']"))
      refute_has(session, css("#artist-form-select-listbox"))
    end

    # BUG 1 regression: both `/multi-select` pickers search
    # `Dev.Music.Artist`, a policy-bearing resource — searching with no
    # `actor:` at all denies the whole read (`Ash.Error.Forbidden`, not a
    # per-row filter), which the component swallows into the generic error
    # state ("Something went wrong. Please try again.") instead of results.
    feature "bug-1: both multi-select pickers show results, not the generic error state",
            %{session: session} do
      session = visit(session, "/multi-select")

      session = click(session, css("#artist-form-multiselect-input"))
      assert_has(session, css("#artist-form-multiselect-listbox [role='option']", minimum: 1))
      refute_has(session, css("#artist-form-multiselect-listbox li", text: "Something went wrong"))

      session = click(session, css("#artist-controlled-multiselect-input"))
      assert_has(session, css("#artist-controlled-multiselect-listbox [role='option']", minimum: 1))
      refute_has(session, css("#artist-controlled-multiselect-listbox li", text: "Something went wrong"))
    end

    # Spec 006/008: the `mod+k` chord opens `Flicker.palette/1` from
    # anywhere on the page, and toggles it closed again.
    feature "spec-006/008: mod+k opens the command palette, and toggles it closed",
            %{session: session} do
      session = visit(session, "/palette")
      wait_for_connected(session)
      modifier = open_chord_modifier(session)

      session = send_chord(session, modifier, "k")
      assert_has(session, css("[role='dialog']"))

      session = send_chord(session, modifier, "k")
      assert_has(session, css("#cmdk[data-open='false']"))
      refute_has(session, css("[role='dialog']"))
    end

    # BUG 2 regression: `mod+k` must resolve to `meta` (Cmd) on macOS
    # regardless of which OS actually runs this suite — spoofing
    # `userAgentData.platform` to `"macOS"` (the real-world Chromium value
    # that a case-sensitive `/Mac/` test never matched, sending `mod+k`
    # through the `ctrl` branch instead) and dispatching a synthetic
    # `metaKey`-only keydown makes this deterministic on any CI runner,
    # independent of `send_keys`' reliance on the actual host OS/keyboard.
    feature "spec-006/008: mod+k resolves to the meta key on macOS (userAgentData.platform reports \"macOS\")",
            %{session: session} do
      session = visit(session, "/palette")
      wait_for_connected(session)

      Wallaby.Browser.execute_script(session, """
      Object.defineProperty(navigator, 'userAgentData', {
        configurable: true,
        value: { platform: 'macOS' }
      })
      """)

      dispatch_chord(session, %{meta: true}, "k")
      assert_has(session, css("[role='dialog']"))

      dispatch_chord(session, %{meta: true}, "k")
      assert_has(session, css("#cmdk[data-open='false']"))
      refute_has(session, css("[role='dialog']"))

      # The old (broken) resolution: `ctrl+k` must NOT also open it once
      # `mod` has correctly bound to `meta` on this spoofed-macOS platform.
      dispatch_chord(session, %{ctrl: true}, "k")
      refute_has(session, css("[role='dialog']"))
    end

    defp dispatch_chord(session, modifiers, key) do
      Wallaby.Browser.execute_script(session, """
      document.dispatchEvent(new KeyboardEvent('keydown', {
        key: #{inspect(key)},
        metaKey: #{modifiers[:meta] == true},
        ctrlKey: #{modifiers[:ctrl] == true},
        altKey: #{modifiers[:alt] == true},
        shiftKey: #{modifiers[:shift] == true},
        bubbles: true
      }))
      """)
    end

    # Spec 007: the open palette traps Tab/Shift+Tab focus inside itself,
    # cycling rather than escaping to the rest of the page, and restores
    # focus to whatever had it before opening once closed.
    feature "spec-007: the open palette traps focus and restores it on close",
            %{session: session} do
      session = visit(session, "/palette")
      wait_for_connected(session)
      session = click(session, css("#cmdk-open-trigger"))
      assert_has(session, css("[role='dialog']"))
      assert active_element_identity(session) == "cmdk-select-input"

      # Opening the palette auto-focuses the nested search input, which
      # (Spec 001's `phx-focus`) kicks off an async record search of its
      # own, landing independently of anything the test does next. Waiting
      # for it to settle here — rather than racing it — keeps the
      # focus-trap assertions below about the trap, not about a coincidental
      # second render arriving mid-Tab.
      assert_has(session, css("#cmdk-select-listbox [role='option']", minimum: 1))

      # Tab from the last focusable element wraps to the first (the close
      # button); Shift+Tab wraps back — never out to the page behind.
      session = send_keys(session, [:tab])
      assert active_element_identity(session) == "Close"

      session = send_keys(session, [:shift, :tab, :shift])
      assert active_element_identity(session) == "cmdk-select-input"

      # Escape closes the whole palette on the first press: a modal overlay
      # is expected to dismiss outright, unlike a bare inline select's
      # two-stage Escape (Spec 001). The nested search's own `.Nav` Escape
      # still fires on the way out (it closes its listbox), but the palette
      # closes regardless — one press, even with the listbox open.
      session = send_keys(session, [:escape])
      assert_has(session, css("#cmdk[data-open='false']"))
      refute_has(session, css("[role='dialog']"))
      # Focus restored to what had it before the palette opened.
      assert active_element_identity(session) == "cmdk-open-trigger"
    end

    # Spec 010: reaching the tail of a `paginate`d listbox — by scroll or
    # by `ArrowDown` on the last option — loads the next window and
    # appends it, rather than replacing `results`.
    feature "spec-010: scrolling the listbox to its tail loads the next window",
            %{session: session} do
      session = session |> visit("/windowed-search") |> click(css("#artist-windowed-select-input"))
      assert_has(session, css("#artist-windowed-select-listbox [role='option']", count: 25))

      Wallaby.Browser.execute_script(session, """
      var listbox = document.getElementById('artist-windowed-select-listbox')
      listbox.scrollTop = listbox.scrollHeight
      """)

      # More than the first window's 25 — the sentinel can legitimately
      # keep firing as appended windows land still-scrolled-to-tail, so an
      # exact count would race the next append.
      assert_has(session, css("#artist-windowed-select-listbox [role='option']", minimum: 26))
    end

    # BUG 3 regression: the active (keyboard-highlighted) option must carry
    # an obvious *visual* state in every shipped preset, not just the
    # `aria-selected` attribute — a multi-class `option_active` string
    # (Tailwind's "bg-indigo-100 text-indigo-900", daisyUI's "bg-primary
    # text-primary-content") crashed `classList.toggle` (which only accepts
    # one token), so the class list, checked here, never actually landed on
    # the option even though `aria-selected` still flipped correctly.
    feature "spec-007/bug-3: ArrowDown gives the active option aria-selected and its theme's visual class, in every preset",
            %{session: session} do
      for preset <- ~w(vanilla tailwind daisy_ui) do
        # The themed showcase renders one preset at a time via `?theme=`.
        s = visit(session, "/themes?theme=#{preset}")
        s = click(s, css("#theme-select-#{preset}-input"))
        assert_has(s, css("#theme-select-#{preset}-listbox [role='option']", minimum: 1))

        s = send_keys(s, [:down_arrow])

        active_option =
          js_value(s, """
          return document.querySelector("#theme-select-#{preset}-listbox [role='option'][aria-selected='true']")?.outerHTML
          """)

        refute is_nil(active_option), "#{preset}: no option carries aria-selected='true' after ArrowDown"

        active_button_classes =
          js_value(s, """
          var option = document.querySelector("#theme-select-#{preset}-listbox [role='option'][aria-selected='true']")
          return option ? Array.from(option.classList) : []
          """)

        refute active_button_classes == [],
               "#{preset}: the highlighted option's button carries no visual class at all"
      end
    end

    # BUG 4 regression: daisyUI's option must show exactly one hover
    # treatment — the preset previously layered its own `hover:bg-base-200`
    # Tailwind utility on the `<li>` on top of daisyUI's built-in `.menu`
    # hover styling on the nested `<button>`, painting two backgrounds at
    # once.
    feature "spec-007/bug-4: hovering a daisyUI option shows exactly one hover treatment",
            %{session: session} do
      session = session |> visit("/themes?theme=daisy_ui") |> click(css("#theme-select-daisy_ui-input"))
      assert_has(session, css("#theme-select-daisy_ui-listbox [role='option']", minimum: 1))

      session = hover(session, css("#theme-select-daisy_ui-listbox [role='option']", count: :any, at: 0))

      li_has_hover_bg =
        js_value(session, """
        var li = document.querySelector("#theme-select-daisy_ui-listbox [role='option']")?.closest("li")
        return li ? li.classList.contains('hover:bg-base-200') : false
        """)

      refute li_has_hover_bg,
             "the <li> itself still carries an explicit hover:bg-base-200 utility class alongside daisyUI's own menu hover"
    end

    feature "spec-010: ArrowDown on the last option loads the next window",
            %{session: session} do
      session = session |> visit("/windowed-search") |> click(css("#constellation-windowed-select-input"))
      assert_has(session, css("#constellation-windowed-select-listbox [role='option']", count: 25))

      # 1 ArrowDown highlights the first option, 24 more walk to the last
      # (index 24 of 25), and the 26th — already sitting on the last
      # option — requests the next window.
      session = send_keys(session, List.duplicate(:down_arrow, 26))

      assert_has(session, css("#constellation-windowed-select-listbox [role='option']", minimum: 26))
    end
  end
end
