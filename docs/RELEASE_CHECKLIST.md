# Release checklist

Per-release obligations — the things that must be *re-done every release*, as
distinct from specs, which describe work done once.

Keeping these here matters for a specific reason: a recurring obligation parked
inside a spec makes that spec permanently un-shippable, because there is no
single moment at which "verified with a screen reader" becomes true forever. The
work is genuinely never finished; it is finished *for this release*. Spec status
answers "is it built"; this file answers "was it checked this time".

Record results per release — a dated section below, or a linked file. Do not
delete previous entries: the history is the evidence.

## Automated gates

Run by `mix check` and CI on every push; listed here so a release manager can
confirm they actually ran green rather than assuming.

- [ ] `mix check` — format, credo strict, dialyzer, sobelow, doctor, tests, docs
- [ ] `mix test --only browser` — Spec 007's axe-core scans and the client-side
      keyboard map, against a real Chrome. Needs a `chromedriver` on `PATH`; the
      CI `browser` job installs one. **Not** part of `mix test`.
- [ ] The `no-ash` CI leg (ADR-006's optional-dependency boundary)
- [ ] The `no-localize` CI leg (ADR-013's display fallback)

## Manual accessibility verification (Spec 007)

The one obligation with no automated substitute. Spec 007's whole premise is
that "we set the ARIA attributes" is not accessibility support — being
*verified pleasant to use with real assistive technology* is. axe-core catches
violations of machine-checkable rules; it cannot tell you whether a facet editor
is comprehensible when you cannot see it.

Work through the script in [`guides/accessibility.md`](../guides/accessibility.md)
(§ "Manual AT test script"), which covers single-select, multi-select, faceted
search, facet editors, invalid values and corrections, counts and recents, and
the command palette.

- [ ] VoiceOver + Safari (macOS) — ⌘F5 toggles VoiceOver
- [ ] NVDA + Firefox (Windows)
- [ ] JAWS + Chrome (Windows) — as licensing allows

For each: record pass/fail per script row, the AT and browser versions, and any
notes. A failure is not a release blocker by itself — an honest, published known
gap is acceptable and is what the accessibility statement is for. An *unrecorded*
pass is not acceptable, because it is indistinguishable from not having run it.

### Results

_No manual AT pass has been recorded yet._ The automated half of Spec 007 has
shipped and is enforced in CI; the manual matrix above has never been executed
against this codebase. That gap is stated in `guides/accessibility.md`'s
statement as a known limitation, and should stay stated until a run lands here.

## Publishing

- [ ] `usage-rules.md` updated if consumer-facing behaviour changed
- [ ] `mix git_ops.release` (generates `CHANGELOG.md` and the tag — never edit
      the changelog by hand)
- [ ] Push the tag
