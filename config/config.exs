import Config

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
  config :flicker, Flicker.Test.Endpoint,
    url: [host: "localhost"],
    secret_key_base: String.duplicate("a", 64),
    live_view: [signing_salt: "flicker-test-signing-salt"],
    render_errors: [formats: [html: Flicker.Test.ErrorHTML], layout: false],
    pubsub_server: Flicker.Test.PubSub,
    server: false

  # `Flicker.Test.PolicyArtist`'s domain (test/support) — a select-component-
  # level actor-scoping fixture, separate from Spec 004's `Dev.Music` harness.
  config :flicker, ash_domains: [Dev.Music, Flicker.Test.PolicyDomain]

  config :phoenix_test, :endpoint, Flicker.Test.Endpoint
end

# `Dev.Endpoint` (dev/) — the dev playground's Bandit-served endpoint
# (Spec 005), only ever started by `Dev.Application` (mix.exs wires it as
# the `:dev`-only `mod` callback).
if config_env() == :dev do
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
    server: true
end
