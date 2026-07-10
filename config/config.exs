import Config

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
