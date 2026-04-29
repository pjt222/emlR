# emlR 0.1.0

First release. Implements the EML (Exp-Minus-Log) Sheffer operator
from Odrzywolek (2026, arXiv:2603.21852) — a single binary operator
`eml(x, y) = exp(x) − log(y)` that, together with the constant `1`,
generates all elementary functions on the principal branch.

## Features

* The operator `eml()` and its real-projection wrapper `eml_real()`.
* Native R AST representation. EML expressions are ordinary `call`
  objects — free interop with `deparse`, `bquote`, `all.vars`, `eval`,
  and `Deriv::Deriv`. There is no custom S3 class.
* Constructors: `eml_const()`, `eml_var()`, `eml_node()`,
  `as_eml_expr()`.
* Predicates: `is_eml_expr()`, `is_eml_call()`, `is_eml_const()`,
  `is_eml_var()`.
* Inspection: `eml_K()` (paper's total node count, matching Table 4 /
  RPN length), `eml_leafcount()` (alternative leaf-only metric),
  `eml_depth()`, `eml_rpn()`.
* Evaluation: `eml_eval()` over `base::eval`, plus a stack-machine
  `compile_eml()` / `run_bytecode()` fast path with deduplicated
  constants pool, vectorised over input bindings.
* Simplifier with two modes:
  - `simplify_eml()` — stays inside the EML grammar (constant folding
    only). Preserves the master-formula completeness invariant.
  - `simplify_native()` — collapses recognised EML patterns to base R
    primitives via rules N1–N7 + algebraic cleanup. The headline check
    `simplify_native(tree_ln("x"))` returns `quote(log(x))` literally.
* Identity catalog: `eml_catalog()` and the `tree_*` constructors,
  with `verify_catalog()` confirming every entry numerically.
* Master formula and symbolic-regression fitter: `build_master()`,
  `master_n_params()`, `unpack_master_params()`,
  `snap_master_params()`, plus `eml_fit()` using L-BFGS-B with
  analytic gradients via `Deriv::Deriv` on the EML-expanded master.
* Selectors: `theta_for_exp()` (depth 1), `theta_for_log()`
  (depth 3, paper Eq. 5).
* Pattern matcher `match_eml()` available as an internal helper for
  rule writers; see `R/07_simplify.R` (not exported).

## Conventions

* `eml_eval()` returns a complex value when `real = FALSE`, even for
  bare-leaf expressions like `eml_eval(2)`. This aligns with
  `run_bytecode()` and SPEC §2.2.
* `eml_K(expr)` is the **total node count** (leaves + interior EML
  nodes), matching the paper's K (Table 4, RPN length). For
  `log(x) = eml(1, eml(eml(1, x), 1))`, `eml_K` returns 7.
  See `reference/ADR-001-K-counting.md`.

## Simplifier coverage

* `simplify_native()` reaches the SPEC §5.2 structural form for **all
  18 catalog entries**, including `sqrt`, `sin`, and `cos`. Closing
  the previous gap required two cleanup-layer additions:
  - rule `C-exp-const-plus-log` (`exp(_C + log(_x)) → exp(_C) * _x`,
    sound on the principal branch via `exp(a+b) = exp(a)·exp(b)` and
    `exp(log(z)) = z`),
  - tolerance-aware atomic equality in the matcher (`|a - b| < 1e-12`)
    plus an asymmetric snap in `.fold_constants` that zeroes a
    sub-tolerance component only when the other component is
    dominantly large. Together these absorb the residual round-off
    from `tree_i() = exp(log(-1)/2)` (which yields `6.12e-17 + 1i`,
    not exact `0+1i`).

## Scope and intentional non-goals

For 0.1.0, the package deliberately scopes to:

* **Two variables.** Univariate and bivariate expressions are the
  tested surface; more variables are not precluded but not exercised.
* **EML only.** The EDL variant `exp(x) / log(y)` and `−eml(y, x)`
  (paper Eq. 4b/4c) are deferred.
* **Master-formula SR.** No tree-topology / genetic-programming
  search. `eml_fit()` operates over the paper's master formula at
  fixed depth.
* **Pure R + Deriv.** No Rcpp / `torch` / parallelisation. The
  bytecode loop vectorises over input bindings; no further hot-path
  acceleration.
* **Principal branch only.** Multi-valued / alternative-branch
  semantics are out of scope.

## Reference materials

The `reference/` directory at the project root (excluded from the
package build) contains the design specification (`SPEC.md`), phased
implementation plan (`IMPLEMENTATION_PLAN.md`), test catalog
(`TESTS.md`), the K-counting decision record
(`ADR-001-K-counting.md`), and an early prototype with a custom-AST
design that this implementation supersedes (`reference/emlR-v1/`).
