# emlR 0.1.0 (in development)

First release. Implements the EML (Exp-Minus-Log) Sheffer operator
from Odrzywolek (2026, arXiv:2603.21852) — a single binary operator
`eml(x, y) = exp(x) − log(y)` that, together with the constant `1`,
generates all elementary functions on the principal branch.

## Features

* The operator `eml()` and its real-projection wrapper `eml_real()`.
* Native R AST representation. EML expressions are ordinary `call`
  objects — free interop with `deparse`, `bquote`, `all.vars`, `eval`,
  and `Deriv::Deriv`. There is no custom S3 class.
* Constructors: `eml_const()`, `eml_var()`, `eml_node()`, `E()`,
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
* Pattern matcher `match_eml()` exposed for advanced use.

## Conventions

* `eml_eval()` returns a complex value when `real = FALSE`, even for
  bare-leaf expressions like `eml_eval(2)`. This aligns with
  `run_bytecode()` and SPEC §2.2.
* `eml_K(expr)` is the **total node count** (leaves + interior EML
  nodes), matching the paper's K (Table 4, RPN length). For
  `log(x) = eml(1, eml(eml(1, x), 1))`, `eml_K` returns 7.
  See `reference/ADR-001-K-counting.md`.

## Known limitations

* `simplify_native()` reaches the SPEC §5.2 expected structural form
  for 15 of 18 catalog entries. The remaining three — `sqrt`, `sin`,
  `cos` — evaluate to the correct numeric value (verified by
  `verify_catalog()`) but retain extra structure. SPEC §5.3 explicitly
  flags Euler-formula cleanup as "arguably outside the simplifier's
  remit". These entries are covered by numeric tests rather than
  structural ones.

## Reference materials

The `reference/` directory at the project root (excluded from the
package build) contains the design specification (`SPEC.md`), phased
implementation plan (`IMPLEMENTATION_PLAN.md`), test catalog
(`TESTS.md`), the K-counting decision record
(`ADR-001-K-counting.md`), and an early prototype with a custom-AST
design that this implementation supersedes (`reference/emlR-v1/`).
