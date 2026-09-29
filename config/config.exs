import Config

# Dev and test resources only. Keeps the string-length counting from before Ash 3.33.
config :ash, default_string_length_count: :mixed

# The seeded `Dev.Music` domain (Spec 004's test harness, Spec 005's
# playground) is only compiled when `ash` is present (`dev/` is added to
# `elixirc_paths(:test)` conditionally — see mix.exs); this config entry is
# just data, so it's harmless to declare even on the no-ash CI leg.
config :flicker, ash_domains: [Dev.Music]

config :git_ops,
  mix_project: Flicker.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/team-alembic/flicker",
  types: [
    tidbit: [
      hidden?: true
    ],
    important: [
      header: "Important Changes"
    ]
  ],
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

# `Flicker.Test.Endpoint` (test/support) is only ever dispatched to
# in-process by `Phoenix.ConnTest`/PhoenixTest — never actually listening on
# a port — so this is the full config it needs.
if config_env() == :test do
  # CI supplies a matched Chrome/driver pair; without explicit paths,
  # hosted runners may mix those with their preinstalled versions.
  wallaby_chromedriver = [
    headless: true,
    path: System.get_env("WALLABY_CHROMEDRIVER_PATH", "chromedriver")
  ]

  wallaby_chromedriver =
    case System.get_env("WALLABY_CHROME_BINARY") do
      nil -> wallaby_chromedriver
      chrome_binary -> Keyword.put(wallaby_chromedriver, :binary, chrome_binary)
    end

  # Cinder's own data load runs in a `start_async` task — a different
  # process from the one that seeded `Dev.Music`'s `private?: true` ETS
  # tables (each calling process gets its own table, see `Dev.Music`'s
  # moduledoc). Without this, a `Cinder.collection` over a `Dev.Music`
  # resource always reads an empty table it can't see into (Spec 009
  # Level 1's `Dev.Live.CinderInterop` recipe). Cinder-only: nothing under
  # `lib/` checks this key, so it doesn't touch Flicker's own async search
  # tasks.
  config :ash, disable_async?: true

  # `Dev.Endpoint` served over real HTTP for the browser suite (Spec 007,
  # `@moduletag :browser`, excluded by default — see
  # `test/support/browser_case.ex`): axe-core and Wallaby both need an
  # actual rendered DOM, which `Phoenix.ConnTest`'s in-process dispatch
  # (`Flicker.Test.Endpoint` above) can't give them. A different port from
  # `Dev.Endpoint`'s `:dev` config below so `mix dev` and the browser suite
  # never collide. Harmless to declare even when the browser tests don't
  # run, and even on the no-ash leg (same reasoning as `ash_domains` above)
  # — `Dev.Application` is still never wired as `:test`'s `mod` callback,
  # so nothing starts this on its own.
  config :flicker, Dev.Endpoint,
    url: [host: "localhost"],
    http: [ip: {127, 0, 0, 1}, port: 4002],
    secret_key_base: String.duplicate("b", 64),
    live_view: [signing_salt: "flicker-browser-signing-salt"],
    render_errors: [formats: [html: Dev.ErrorHTML], layout: false],
    pubsub_server: Dev.PubSub,
    adapter: Bandit.PhoenixAdapter,
    check_origin: false,
    server: true

  config :flicker, Flicker.Test.Endpoint,
    url: [host: "localhost"],
    secret_key_base: String.duplicate("a", 64),
    live_view: [signing_salt: "flicker-test-signing-salt"],
    render_errors: [formats: [html: Flicker.Test.ErrorHTML], layout: false],
    pubsub_server: Flicker.Test.PubSub,
    server: false

  # `Flicker.Test.PolicyArtist`'s domain (test/support) — a select-component-
  # level actor-scoping fixture, separate from Spec 004's `Dev.Music` harness.
  # `Flicker.Test.FacetDomain` (test/support) is the equivalent fixture for
  # Spec 003's faceted-search components.
  config :flicker, ash_domains: [Dev.Music, Flicker.Test.PolicyDomain, Flicker.Test.FacetDomain]

  config :phoenix_test, :endpoint, Flicker.Test.Endpoint

  # `Dev.Endpoint` (dev/) — the dev playground's Bandit-served endpoint
  # (Spec 005), only ever started by `Dev.Application` (mix.exs wires it as
  # the `:dev`-only `mod` callback).
  config :wallaby,
    otp_app: :flicker,
    driver: Wallaby.Chrome,
    chromedriver: wallaby_chromedriver,
    max_wait_time: 8_000,
    # See the matching `:test` config above — the same private-ETS/async-task
    # mismatch shows up live in the browser too.
    base_url: "http://localhost:4002"
end

if config_env() == :dev do
  config :ash, disable_async?: true

  config :flicker, Dev.Endpoint,
    url: [host: "localhost"],
    http: [ip: {127, 0, 0, 1}, port: 4000],
    secret_key_base: String.duplicate("d", 64),
    live_view: [signing_salt: "flicker-dev-signing-salt"],
    render_errors: [formats: [html: Dev.ErrorHTML], layout: false],
    pubsub_server: Dev.PubSub,
    adapter: Bandit.PhoenixAdapter,
    check_origin: false,
    debug_errors: true,
    server: true,
    code_reloader: true,
    live_reload: [
      patterns: [
        ~r"dev/.*(ex|heex)$",
        ~r"lib/flicker/.*(ex|heex)$",
        ~r"lib/flicker\.ex$"
      ]
    ]
end
