# ADR-002: `simplify_native` rewrites top-down, not bottom-up

**Status:** Accepted
**Date:** 2026-05-29
**Context:** SPEC §3.3 design sketch vs as-shipped simplifier

## Decision

`simplify_native` applies its rewrite rules **top-down** (parent before
children), iterated to a fixed point. The original SPEC §3.2/§3.3 phrasing
"applied bottom-up, repeatedly to a fixed point" is superseded by this ADR.
The as-shipped rule set also extends the SPEC's N1–N7 table:

- **N3 is tried before N1.** General rule N1 (`eml(_x, 1) -> exp(_x)`)
  must not pre-empt the more specific N3 (`eml(1, eml(eml(1, _x), 1)) ->
  log(_x)`).
- **`N5b`** is added (a sibling of N5).
- An **algebraic-cleanup layer** (`.native_cleanup_rules()`, the `C-*`
  rules) runs after the EML rules, including the Euler `E1`/`E2` trig
  collapses and the principal-branch-guarded log/exp rules.

`R/07_simplify.R` is authoritative; the SPEC tables are a design sketch.

## Background

Invariant **I2** requires the sacred `log` form to round-trip exactly:

```
simplify_native(quote(eml(1, eml(eml(1, x), 1))))  # must be log(x)
```

A **bottom-up** pass visits the inner subtree `eml(eml(1, x), 1)` first.
N1 matches it (`eml(_x, 1) -> exp(_x)`) and fires, producing
`eml(1, exp(eml(1, x)))` — after which N3 can never match the original
whole-tree shape, and the result collapses toward `exp(...)` rather than
`log(x)`. I2 is violated.

A **top-down** pass visits the whole tree first, where N3 matches and
fires, yielding `log(x)` directly. The shipped code documents this at
`R/07_simplify.R:11-17`.

## Options considered

**A. Keep SPEC's bottom-up wording; "fix" the code to match.**
   - Con: would break I2 (the package's primary correctness check). Not
     viable — the spec is wrong here, not the code.

**B. Correct the code's behaviour silently, leave SPEC as-is.**
   - Con: SPEC declares itself normative ("deviations require justification
     in NEWS.md or an ADR", SPEC §intro). Leaving it stale is a real hazard
     for any future re-implementer following §3.3 literally.

**C. Record the top-down decision in an ADR, annotate SPEC §3.3, and keep
   `R/07_simplify.R` authoritative.**
   - Pro: preserves the spec as a design record while making the binding
     behaviour unambiguous; satisfies the spec's own deviation clause.

## Decision rationale

Option C. The code is correct (I2 holds at runtime, all catalog identities
round-trip, the full test suite and the depth-3 SR-recovery gate pass). The
defect was purely documentary drift: the pre-implementation SPEC was never
reconciled with the as-shipped simplifier. Documentation correctness is
treated as code correctness.

## Consequences

- SPEC §3.2/§3.3 now carry a normative correction pointing here; the §3.3
  "open question" about the N4/N7 overlap is marked resolved (N4 precedes
  N7 in `.native_rules()`).
- `IMPLEMENTATION_PLAN.md` §4c updated from "bottom-up" to "top-down".
- The principal-branch log-combine rules were further hardened (the bare
  `C-log-prod`/`C-log-quot` were replaced by `exp`-wrapped
  `C-exp-log-prod`/`C-exp-log-quot` plus `C-exp-log-minus-const`) so that
  an exposed `log(a) - log(b)` is never combined to `log(a/b)`, which would
  lose `2*pi*i` on the principal branch and break I3.

## References

- `R/07_simplify.R:11-17` — top-down rationale in source.
- SPEC §3.3 — normative-correction note.
- Paper Eq. 5: `log(x) = eml(1, eml(eml(1, x), 1))`, K = 7.
- Invariants I2 (sacred identities) and I3 (principal branch) in
  `.claude/CLAUDE.md`.
