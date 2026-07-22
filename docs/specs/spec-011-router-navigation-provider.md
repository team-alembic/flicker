---
status: draft
date: 2026-07-22
depends_on: [spec-008, adr-001, adr-006]
---

# Spec 011: Router navigation provider — every page in the palette with one flag

Phoenix interop for the palette: derive navigable destinations from the
host's own `Phoenix.Router`, so `⌘K → type a page name → Enter → you're
there` works for *pages*, not just records, with one line of config. The
cmdk/DocSearch experience covers both "take me to a record" and "take me to
a screen"; today Flicker only does the former unless the host hand-writes a
provider listing their routes — which drifts the moment a route changes.

## Sketch

```heex
<Flicker.palette
  source={{Flicker.Providers.Routes, router: MyAppWeb.Router}}
  ...
/>
```

or federated alongside records via a combining provider — routes as one
more `group` ("Pages") in the same palette.

## Scope (to be refined before `ready`)

- **`Flicker.Providers.Routes`** — a provider deriving its results from
  `Phoenix.Router.routes/1` introspection: `GET`/`live` routes become
  `%Flicker.Result{label, meta: %{href: path}, group: "Pages"}`, searched
  by a humanised label derived from the path/helper name, navigating via
  the existing Spec 008 `meta.href` convention. Zero per-route config.
- **Filtering, not everything**: verbs other than GET, params-bearing
  paths (`/artists/:id` — nothing to navigate to without an id), and
  framework routes (`/dev/...`, LiveDashboard) are excluded by default.
  Options: `only:`/`except:` (path globs), `label:` (fn route -> String),
  and explicit `extra:` entries for parameterised favourites.
- **Labels that read well**: `/user-settings/billing` → "User settings ·
  Billing". Derivation is dumb-but-predictable; `label:` overrides where
  the host cares.
- **Authorisation honesty**: routes are not policy-scoped — a router knows
  paths, not permissions. The spec must be explicit that this provider
  lists what it's given; hosts gate sensitive destinations via `only:`/
  `except:` or a `visible?: fn route, actor -> boolean` option. This is
  the sharp edge of the feature — needs real design before `ready`.
- **Composition**: works standalone or merged with record search. Whether
  merging is a blessed `Flicker.Providers.Merge` (results from N providers,
  grouped) or a documented recipe is an open question — Merge is broadly
  useful beyond routes (it's the federated-search pattern generalised).

## Non-goals

- Command execution (actions in the palette) — still its own future spec.
- Crawling page *content* — this is route names, not site search.
- Nested/param route wizardry (`/artists/:id` prompting for an artist) —
  that's a composition of this + record search, later.

## Open questions

- `Phoenix.Router.routes/1` output shape across Phoenix versions — verify
  the introspection surface is stable enough to build on (it's public).
- Compile-time (routes baked at build) vs runtime introspection —
  runtime is simpler and routers rarely change at runtime; verify cost.
- `Flicker.Providers.Merge` as part of this spec or its own?
- Does `visible?/2` belong here, or is an actor-aware wrapper provider the
  cleaner ADR-004-consistent story?
