defmodule Dev.Layouts do
  @moduledoc """
  The dev playground's root layout (Spec 005) — a nav bar linking to every
  capability page, Tailwind + daisyUI via CDN (no asset pipeline), and the
  LiveView client loaded from a CDN as ES modules.
  """

  use Phoenix.Component

  @nav [
    {"/", "Home"},
    {"/single-select", "Single select"},
    {"/static-provider", "Static provider"},
    {"/themes", "Themes"},
    {"/edge-states", "Edge states"}
  ]

  @doc "The root HTML document wrapping every playground page's `@inner_content`."
  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    assigns = assign(assigns, :nav, @nav)

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Flicker dev playground</title>
        <script src="https://cdn.tailwindcss.com">
        </script>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/daisyui@4/dist/full.min.css" />
        <script type="module">
          import {Socket} from "https://esm.sh/phoenix@1.8.9?bundle"
          import {LiveSocket} from "https://esm.sh/phoenix_live_view@1.2.6?bundle"

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})

          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body class="min-h-screen bg-white text-gray-900">
        <nav class="border-b border-gray-200 px-4 py-3">
          <ul class="flex flex-wrap gap-4 text-sm">
            <li :for={{path, title} <- @nav}>
              <.link navigate={path} class="text-indigo-600 hover:underline">{title}</.link>
            </li>
          </ul>
        </nav>
        <main class="p-6">
          {@inner_content}
        </main>
      </body>
    </html>
    """
  end
end
