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
