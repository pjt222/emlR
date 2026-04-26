# emlR2 — handoff package

Documentation and design materials for **emlR2**, an R implementation of
the EML Sheffer operator from
[arXiv:2603.21852](https://arxiv.org/abs/2603.21852) (Odrzywołek, 2026).

This folder is a **handoff package for Claude Code**. It is not source
code — it is the specification, plan, and tests that Claude Code should
work from to produce v2 of the package.

## How to use this package

Open a Claude Code session in this directory (or wherever you place these
files) and start with:

```
Read CLAUDE.md, then SPEC.md, then IMPLEMENTATION_PLAN.md. Then begin
Phase 0 from the plan.
```

Claude Code should work phase-by-phase, running tests after each phase,
and not advancing until the phase's acceptance criteria are met.

## File map

| File                        | Purpose                                       | Read order |
|-----------------------------|-----------------------------------------------|------------|
| `CLAUDE.md`                 | Top-level guidance, invariants, style         | 1          |
| `SPEC.md`                   | Full technical specification                  | 2          |
| `IMPLEMENTATION_PLAN.md`    | Phased plan with acceptance criteria          | 3          |
| `TESTS.md`                  | Test catalog with concrete expected values    | 4          |
| `REFERENCES.md`             | Paper, related code, derivation receipts      | as needed  |
| `reference/emlR-v1/`           | v1 prototype (correct, slow, wrong AST)       | as needed  |

## What v2 delivers over v1

1. **Native R AST** instead of a custom `eml_tree` S3 class. Free interop
   with `deparse`, `bquote`, `Deriv`, `eval`.
2. **Peephole simplifier** with the paper's identities as rewrite rules.
   Two modes: stays-in-EML and collapses-to-base-R. The native-mode
   simplifier collapsing `tree_log("x")` to `log(x)` literally is the
   package's headline correctness check.
3. **Bytecode compiler and stack-machine evaluator** — flat instruction
   stream, vectorised, ~50× faster on long input vectors.
4. **Symbolic differentiation via `Deriv`** for analytic gradients of
   the master formula. Replaces v1's SANN with L-BFGS-B; ~100× faster
   convergence at depth 3.
5. **Real `testthat` test suite**, replacing v1's hand-rolled assertion
   script.

## What v2 does NOT add

- New mathematics. Every result is from the paper.
- Heavy dependencies. Only `Deriv` (CRAN, lightweight).
- Non-base R idioms. No tidyverse, no Rcpp, no torch.
- The ternary operator T(x,y,z) or the EDL/−EML variants. Out of scope.

## Status

Specification complete. Ready for implementation.

Estimated effort: ~10 hours of focused implementation, plus 2-3 hours
for the simplifier (Phase 4 always overruns). The simplifier alone
constitutes a meaningful improvement over v1 and can ship as v2.0.0
even if the bytecode compiler (Phase 3) and L-BFGS fitter (Phase 5)
are deferred to later releases.

## License

CC BY 4.0, mirroring the paper's license. All mathematical results are
due to Odrzywołek; this package is an independent R implementation.
