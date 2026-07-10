---
status: draft # draft | ready | in-progress | shipped
date: YYYY-MM-DD
depends_on: [] # spec/ADR files this builds on, e.g. [spec-001, adr-002]
---

# Spec NNN: Title

One-paragraph summary: what capability this adds and why.

## Scope

What's in. Bullet the user-visible behaviour and the public API surface
(component attrs, callbacks, config) this spec introduces or changes.

## Non-goals

What's deliberately out, especially things a reader might assume are in.

## Design

The how, in enough detail that an agent can implement without asking
questions. Code sketches for the public API. Link relevant ADRs rather than
restating decisions.

## Acceptance criteria

Checkable statements ("an edit form opening with three ids set labels all
three with one query"), not vibes. These become the test list.

## Open questions

Anything unresolved. A spec can be `ready` with open questions only if they
don't block the core path.
