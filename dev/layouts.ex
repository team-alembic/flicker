defmodule Dev.Layouts do
  @moduledoc """
  The dev playground's root layout (Spec 005) — the static HTML shell
  (Tailwind + daisyUI via CDN, no asset pipeline, the LiveView client
  loaded from a CDN as ES modules). The sidebar nav, page header, and
  active-page state live in `Dev.UI.page/1` instead: this shell only ever
  renders once per dead render, so anything needing to update across
  `live_navigate` (like which nav link is active) has to live inside the
  LiveView's own template, not here.
  """

  use Phoenix.Component

  @doc "The root HTML document wrapping every playground page's `@inner_content`."
  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme="light">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <%!--
          Pinned light rendering: without `data-theme="light"`, daisyUI's
          stylesheet auto-switches every unstyled native control (the
          search inputs, the latency `<input type="number">`) to its dark
          theme whenever the visiting browser/OS prefers dark —
          `@media (prefers-color-scheme: dark)` in daisyUI's own CSS, not
          something `color-scheme` (below) touches — while the rest of the
          page stays the light Tailwind palette, an unreadable ~1.6:1
          contrast axe correctly flags as a violation (Spec 007). The
          `color-scheme` meta pins native (non-daisyUI) form-control
          rendering the same way, belt and braces. The playground has no
          real dark theme of its own (a Tailwind/daisyUI CDN page, not the
          shipped library), so pinning light is the fix, not chasing
          per-theme input colors.
        --%>
        <meta name="color-scheme" content="light" />
        <title>Flicker dev playground</title>
        <script src="https://cdn.tailwindcss.com">
        </script>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/daisyui@4/dist/full.min.css" />
        <%!--
          An import map, so the bare `"phoenix-colocated/flicker"` specifier
          `Phoenix.LiveView.ColocatedHook`'s generated manifest expects a
          bundler to resolve (see that module's docs) resolves natively in
          the browser instead — this playground has no bundler. Without
          this, `phx-hook="..."` has nothing to attach to `LiveSocket`, and
          every colocated hook (`.Nav`, `.Palette`, `.FlickerSearchNav` —
          all of Spec 001/006/008/010's client-side keyboard behaviour)
          silently never mounts. `Dev.Endpoint` serves the manifest — see
          its `Plug.Static` mount.
        --%>
        <script type="importmap">
          {"imports": {"phoenix-colocated/flicker": "/phoenix-colocated/flicker/index.js"}}
        </script>
        <script type="module">
          import {Socket} from "https://esm.sh/phoenix@1.8.9?bundle"
          import {LiveSocket} from "https://esm.sh/phoenix_live_view@1.2.6?bundle"
          import {hooks as flickerHooks} from "phoenix-colocated/flicker"

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {hooks: flickerHooks, params: {_csrf_token: csrfToken}})

          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body class="min-h-screen bg-white font-sans text-gray-900 antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end
end
