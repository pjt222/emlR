# CLAUDE.md — emlR

Project-level guidance for Claude Code working on this repository.

## What this project is

An R implementation of the EML (Exp-Minus-Log) Sheffer operator from
**Odrzywołek (2026), arXiv:2603.21852**. The paper proves that a single
binary operator `eml(x, y) = exp(x) − ln(y)` together with the constant `1`
generates all elementary functions. This package operationalises that result
for symbolic manipulation, symbolic regression, and pedagogical exploration
in R.

This is a **first-release package** (target: 0.1.0 on CRAN). An early
exploratory prototype lives at `reference/emlR-v1/` (correct but slow,
custom nested-list AST that duplicates work R's `call` system already
does for free). The current implementation re-grounds the representation
in native R AST objects, adds a peephole simplifier with the paper's
identities as rewrite rules, and compiles to RPN bytecode for batched
evaluation. The prototype is preserved as a design reference and
should not be promoted to a public predecessor — it has never been
released.

## Author context

The user is Philipp, a Senior Data Scientist with strong R + Python ML
background. He uses R idiomatically (tidyverse, lavaan, ggplot2, Deriv) and
expects code that respects R conventions: S3 methods over switch/dispatch,
`call`/`name` objects over parallel ASTs, `deparse`/`bquote`/`substitute`
over string manipulation, vectorisation over loops. He has read the paper;
he doesn't need it re-explained.

He runs R locally and will execute tests himself.

## Invariants

These properties must hold throughout. If a change would violate one of
these, stop and surface it as a question rather than break the invariant.

**I1. Mathematical correctness over uniformity.** The paper's beautiful
property is that every node is identical. Practical R code does not need
to preserve this at runtime — it needs to *be able to* preserve it (for
the master formula and the SR search space). The simplifier may break
EML-uniformity to produce a fast execution plan; the canonical tree must
remain available for inspection.

**I2. Three identities are sacred.** These are stated verbatim in the
paper and must round-trip exactly through any simplifier:
- `eml(x, 1)` ↔ `exp(x)`
- `eml(1, 1)` ↔ `e`
- `eml(1, eml(eml(1, x), 1))` ↔ `log(x)` (paper Eq. 5, K=7)

If `simplify_native(canonical_form_of(log))` does not yield `log(x)`
literally, the simplifier is wrong. This is the package's primary
correctness check — every catalog identity, when canonicalised then
simplified, must collapse to its native R primitive.

**I3. Complex-domain semantics on the principal branch.** Trig
functions, π, and i all require `log(-1) = iπ`. Any evaluation path
must coerce through `as.complex()` or use a complex-aware code path.
R's default `log(-1)` returns `NaN`; this is wrong for EML.

**I4. Extended-real semantics matter.** Several constructions use
`log(0) = -Inf` and `exp(-Inf) = 0`, e.g. `−1 = exp(log(0)) − log(exp(1))`.
R complex arithmetic gets this right; do not "fix" the resulting `-Inf`
intermediate values without checking the paper's §4.1.

**I5. The SR master formula must remain complete.** Aggressive
simplification that escapes the EML grammar would produce a faster
evaluator but a *smaller* SR search space than the paper's completeness
proof guarantees. The compile pipeline therefore has two modes:
"strict" (`simplify_eml()`, stays inside EML, used for SR training)
and "fast" (`simplify_native()`, collapses to base R, used for
inspection and verification).

## What is delivered

1. **Native R AST representation.** EML expressions are R `call`
   objects with the function name `eml`. Free interop with `deparse`,
   `bquote`, `substitute`, `all.vars`, `Deriv::Deriv`, `eval`.
2. **Peephole simplifier** with rewrite rules drawn from the paper's
   identity chain (Fig. 1), implemented as pattern-matching on call
   objects. Two modes: `simplify_eml()` (stays in EML) and
   `simplify_native()` (collapses to base R primitives).
3. **RPN bytecode compiler** producing a flat instruction vector +
   constants table for batched evaluation. The instruction set is
   documented in `reference/SPEC.md` §4. Evaluation is a single tight
   R loop over instructions operating on whole vectors of input.
4. **Symbolic differentiation pipeline.** The master formula is
   expanded `eml(a, b) → exp(a) − log(b)` before passing to
   `Deriv::Deriv`, giving analytic gradients for L-BFGS-B.
5. **Test suite** covering every catalog identity round-trips, the SR
   master formula recovers `log(x)` at depth 3 (≥8/10 multi-restart),
   simplifier idempotence on every catalog entry, bytecode evaluator
   agrees with `eml_eval()` on randomised trees.

## Constraints

- Base R + `Deriv` only. No tidyverse, no Rcpp, no torch.
- Do not "improve" the canonical identities by replacing them with
  K-shorter forms invented on the spot. The paper's K-optimal trees
  came from exhaustive search; the catalog constructions are not
  optimal but are *correct* and *traceable*. If a shorter form is
  desired, cite the source (paper Table 4 row, or independent
  derivation with proof).
- The `reference/emlR-v1/` prototype is a design reference; do not
  copy its custom-AST code into the package.

## Style

- Roxygen doc comments on every exported function (`@export`, `@param`,
  `@return`, `@examples` where short).
- S3 dispatch via class attributes, not `switch(type, ...)`.
- snake_case throughout.
- 80-column soft limit, 100 hard.
- No `magrittr` pipes; native `|>` only if it improves clarity.
- Comments explain *why*, not *what*. The code says what.

## Common workflows

```bash
# Build and check (zero errors/warnings/notes expected)
cd /mnt/d/dev/p && R CMD build emlR && R CMD check emlR_*.tar.gz

# Run tests directly (faster iteration)
NOT_CRAN=true Rscript -e '
  library(testthat); for (f in list.files("R", "\\.R$", full.names=TRUE)) source(f);
  test_dir("tests/testthat", reporter = "summary")'

# Run the slow Phase-5 8/10 SR-recovery gate (~1 min)
EMLR_RUN_SLOW=true NOT_CRAN=true Rscript -e '...'   # see test-master.R

# Regenerate man/ pages and NAMESPACE after changing roxygen comments
Rscript -e 'roxygen2::roxygenize(".")'
```

## Reference materials

- `reference/SPEC.md` — full technical specification
- `reference/IMPLEMENTATION_PLAN.md` — phased plan with acceptance criteria
- `reference/TESTS.md` — test catalog with expected values
- `reference/REFERENCES.md` — paper, related implementations, derivations
- `reference/ADR-001-K-counting.md` — K = total node count vs leaf count
- `reference/emlR-v1/` — early prototype (correct, slow, custom AST)

The paper itself: https://arxiv.org/abs/2603.21852
