# Implementation plan

Six phases. Each has explicit acceptance criteria. **Do not advance to the
next phase until the current phase's tests pass.**

---

## Phase 0 — Project skeleton (~30 min)

Set up the package structure. No logic yet.

```
emlR2/
├── DESCRIPTION
├── NAMESPACE
├── R/
│   ├── 00_imports.R         # @importFrom Deriv Deriv
│   ├── 01_core.R            # eml(), eml_real()
│   ├── 02_constructors.R    # eml_const, eml_var, eml_node, E, as_eml_expr
│   ├── 03_predicates.R      # is_eml_*
│   ├── 04_inspect.R         # eml_K, eml_depth, eml_rpn
│   ├── 05_eval.R            # eml_eval (via base::eval)
│   ├── 06_compile.R         # compile_eml + run_bytecode
│   ├── 07_simplify.R        # match_eml + simplify_eml + simplify_native
│   ├── 08_identities.R      # tree_*, eml_catalog, verify_catalog
│   ├── 09_master.R          # build_master, params, eml_fit
│   └── 99_compat_v1.R       # shim
├── tests/
│   └── testthat/
│       ├── test-core.R
│       ├── test-eval.R
│       ├── test-bytecode.R
│       ├── test-simplify.R
│       ├── test-identities.R
│       └── test-master.R
├── NEWS.md
├── README.md
└── CLAUDE.md
```

**Acceptance:** `R CMD check` passes with zero errors, zero warnings.
Empty test files OK at this point.

---

## Phase 1 — Core operator and AST (~1 hour)

Implement:
- `eml(x, y)` — copy from v1, no changes
- `eml_real(x, y, tol)` — copy from v1
- Constructors: `eml_const`, `eml_var`, `eml_node`, `E`, `as_eml_expr`
- Predicates: `is_eml_expr`, `is_eml_call`, `is_eml_const`, `is_eml_var`
- Inspection: `eml_K`, `eml_depth`, `eml_rpn`

Tests (`test-core.R`):
- `eml(1, 1)` returns complex with `Re ≈ e`, `Im ≈ 0`
- `eml(0, 1)` returns `1+0i`
- `eml_real(1, 1)` returns `e` numerically
- `eml_real(eml(1, 0), 1)` returns `Inf` (warns about imag if any)
- `as_eml_expr(2)` returns `2` numerically (passes through)
- `as_eml_expr("x")` returns `as.name("x")`
- `as_eml_expr(quote(eml(1, x)))` returns the same call (passes through)
- `eml_node(1, "x")` returns `quote(eml(1, x))`
- `eml_K(quote(eml(1, eml(eml(1, x), 1))))` returns 7 (matches paper Eq. 5)
- `eml_depth(quote(eml(1, eml(eml(1, x), 1))))` returns 3
- `eml_rpn(quote(eml(1, eml(eml(1, x), 1))))` returns `"1 1 x E 1 E E"` (7 tokens, matches paper)

**K-counting note (correction to v1):** The v1 implementation defined
`eml_K` as a leaf count, returning 4 for `ln(x) = eml(1, eml(eml(1, x), 1))`.
The v1 README and comments claimed this matches the paper's K=7 — that
was a v1 documentation error.

The paper (Table 4, Eq. 5) defines K as "RPN code length" — the number
of tokens in the postfix serialization. For ln(x) the RPN is
`1, 1, x, eml, 1, eml, eml` which is 7 tokens: 4 literals + 3 eml nodes.

In v2, define `eml_K(expr)` as **total node count** (leaves + interior),
matching the paper:
- `eml_K(quote(eml(1, eml(eml(1, x), 1))))` returns 7
- `eml_K(quote(eml(x, 1)))` returns 3 (matches paper for exp)
- `eml_K(quote(eml(1, 1)))` returns 3 (matches paper for e)

This is a behaviour change from v1. Document in NEWS.md. Add a deprecated
`eml_leafcount(expr)` for users who relied on v1's count, and an
`eml_nodecount` alias for clarity.

For RPN: `eml_rpn(quote(eml(1, eml(eml(1, x), 1))))` returns
`"1 1 x E 1 E E"` — 7 tokens, matching the paper exactly.

**Acceptance:** All `test-core.R` tests pass. `eml_K` of every v1 catalog
entry equals the v1 value.

---

## Phase 2 — Evaluation (~1 hour)

Implement `eml_eval(expr, vars, real, tol)`. Internally:

```r
eml_eval <- function(expr, vars = list(), real = FALSE, tol = 1e-8) {
  env <- list2env(c(list(eml = eml), vars), parent = baseenv())
  z <- eval(expr, envir = env)
  if (real) {
    if (any(abs(Im(z)) > tol, na.rm = TRUE))
      warning("imag residue exceeds tol")
    Re(z)
  } else {
    z
  }
}
```

Tests (`test-eval.R`):
- Every v1 catalog identity, evaluated, matches its expected numeric value
  to 1e-8. Port the assertion table from `reference/emlR-v1/tests/test_eml.R`.
- Vectorised input: `eml_eval(quote(eml(x, 1)), list(x = c(0, 1, 2)))`
  returns `c(1, e, e^2)`-ish (complex).
- `real = TRUE` returns numeric for real-valued identities.
- `real = TRUE` warns when imag residue is large (e.g. evaluating
  `eml(1, -1)` which legitimately produces a complex result).

**Acceptance:** `tests/testthat/test-eval.R` passes. All v1 identities
evaluate correctly through the new `eval()`-based path.

---

## Phase 3 — Bytecode compiler and evaluator (~2 hours)

Implement `compile_eml(expr)` and `run_bytecode(bc, vars)` per SPEC §4.

Test plan (`test-bytecode.R`):

1. **Round-trip identity:** for 100 random EML trees of depths 1-6,

   ```r
   v1 <- eml_eval(expr, vars)
   v2 <- run_bytecode(compile_eml(expr), vars)
   expect_equal(v1, v2, tolerance = 1e-12)
   ```

   Random tree generator helper: `random_eml_tree(max_depth, vars)` that
   recursively picks `1`, a variable, or `eml(L, R)` with probability
   weighted by remaining depth.

2. **Stack depth correctness:** the preallocated stack size matches the
   running max during execution. Add an assertion in dev mode.

3. **Vectorisation:** `run_bytecode(bc, list(x = runif(10000)))` returns
   a complex vector of length 10000. Time it; should be <100ms for a K=7
   tree.

4. **Bytecode inspection:** `compile_eml(quote(eml(1, eml(eml(1, x), 1))))$ops`
   has length 7 and contains opcodes in the right order (LIT-LIT-LIT-VAR-EML-LIT-EML-EML
   ... wait, recount: that's 8 ops because one of the `1`s appears twice).

   Actually let me trace: post-order emit for `eml(1, eml(eml(1, x), 1))`:
   - visit `1` (root.left) → LIT 1
   - visit `eml(eml(1, x), 1)` (root.right):
     - visit `eml(1, x)` (its left):
       - visit `1` → LIT 1
       - visit `x` → VAR x
       - emit EML
     - visit `1` (its right) → LIT 1
     - emit EML
   - emit EML

   That's: LIT, LIT, VAR, EML, LIT, EML, EML — 7 ops. ✓ Matches K=7 and
   the paper's RPN string.

   Add this as a specific test case.

5. **Constants pool dedup:** `compile_eml(quote(eml(1, eml(1, x))))$consts`
   has length 1 (just `1+0i`), not 2. Both LIT ops point to index 1.

**Acceptance:** all bytecode tests pass; equivalence test §4.5 of SPEC
passes on 100 random trees.

---

## Phase 4 — Simplifier (~3 hours)

The hardest phase. Build the pattern matcher first, test it independently,
then add rewrite rules one at a time with tests for each.

Sub-phases:

### 4a. `match_eml(expr, pattern)`

```r
match_eml(quote(eml(1, x)), quote(eml(1, `_x`)))  # -> list(`_x` = quote(x))
match_eml(quote(eml(1, x)), quote(eml(`_x`, 1)))  # -> NULL
match_eml(quote(eml(x, x)), quote(eml(`_x`, `_x`))) # -> list(`_x` = quote(x))
match_eml(quote(eml(x, y)), quote(eml(`_x`, `_x`))) # -> NULL  (binding conflict)
```

Test thoroughly. The matcher is the foundation; bugs here cascade.

### 4b. `simplify_eml`

Only constant folding. Five-line implementation:

```r
simplify_eml <- function(expr) {
  if (!is.call(expr)) return(expr)
  if (length(all.vars(expr)) == 0) return(eval(expr, list(eml = eml)))
  call("eml", simplify_eml(expr[[2]]), simplify_eml(expr[[3]]))
}
```

Tests: applied to `eml(1, 1)` returns numeric `e`. Applied to
`eml(x, 1)` returns itself. Idempotent on all catalog entries.

### 4c. `simplify_native` core rules

Rules N1-N7 from SPEC §3.3, applied bottom-up to fixed point.

Tests, one per rule:
- N1: `simplify_native(quote(eml(x, 1)))` → `quote(exp(x))`
- N2: `simplify_native(quote(eml(1, 1)))` → `exp(1)` numerically (= e)
- N3: `simplify_native(quote(eml(1, eml(eml(1, x), 1))))` → `quote(log(x))`
- N4: `simplify_native(quote(eml(log(x), exp(y))))` → `quote(x - y)`

### 4d. Idempotence test (CRITICAL)

For every catalog entry, applying `simplify_native` twice gives the same
result as applying it once. If this fails, the rule set is non-confluent
and you must debug with `trace = TRUE`.

### 4e. The big test

`simplify_native(tree_log("x"))` returns `quote(log(x))` literally.
This is the headline correctness check for the whole package.

Then add for every catalog entry the matching expected native form (SPEC §5.2).

### 4f. Euler rules (E1, E2)

Add rules for sin/cos to clean up the complex-exponential constructions.
Optional but strongly recommended for the SR demo readability.

**Acceptance:** `verify_catalog()` returns TRUE for every entry. This is
the gate.

---

## Phase 5 — Master formula and SR (~2 hours)

Implement per SPEC §6.

### 5a. `build_master(depth, var_name)`

Produces a `call` expression with parameter symbols `alpha_<i>`, `beta_<i>`,
`gamma_<i>`. Test by depth:
- depth 1: 4 parameters (2 leaves × 2 each)
- depth 2: 14 parameters (2 inner slots × 3 + 4 leaf slots × 2 = 14, matches `5*2^2 - 6 = 14`)
- depth 3: 34 parameters (matches `5*2^3 - 6 = 34`)

### 5b. `theta_for_log()` selector

A specific parameter vector that makes `build_master(3)` evaluate to
`log(x)` exactly. Verify by evaluation on test points.

### 5c. Differentiation pipeline

For every parameter symbol `p`, compute `Deriv::Deriv(expanded_expr, p)`.
Cache the gradient expressions; recompute only when the master formula
structure changes.

Test: numerical gradient via finite differences agrees with analytic
gradient to 1e-6 at random parameter values, on a depth-2 master formula.
This is the gradient-correctness check.

### 5d. `eml_fit` with L-BFGS-B

Replace v1's SANN. Loss is MSE; gradient is the chained analytic Jacobian.
Verify on the paper's depth-3 ln(x) recovery example: 30 points,
`xs = seq(0.5, 5, length.out = 30)`, `ys = log(xs)`. Expect snap_mse near
machine epsilon squared, post-snap.

Run with `n_restarts = 10`. The paper reports ~25% success at depth 3;
with 10 restarts, expect ≥1 success in nearly every run (probability of
all 10 failing ≈ 0.75^10 ≈ 6%).

**Acceptance:** ln(x) is recovered exactly (snapped MSE < 1e-20) in at
least 8 of 10 runs with random seeds.

---

## Phase 6 — Compatibility shim and docs (~1 hour)

### 6a. `compat_v1.R`

Old `eml_tree` list constructors return `call` objects with a one-time
`.Deprecated()` warning. Old `format.eml_tree` works because it's now
the default `deparse`. Old test script runs unchanged.

### 6b. NEWS.md

Document the API changes:
```
# emlR 2.0.0
* AST representation changed from custom S3 list to native R `call` objects.
* New: bytecode compiler and evaluator (~50× faster on long input vectors).
* New: peephole simplifier with native-mode collapsing to base-R primitives.
* New: L-BFGS-B fitter with analytic gradients via Deriv (~100× faster than v1 SANN).
* Deprecated: `eml_tree` constructor (returns a `call` with a warning).
```

### 6c. README.md

Replace the v1 README with one that:
1. States the paper, in one paragraph.
2. Shows the simplest possible usage:
   ```r
   library(emlR2)
   simplify_native(quote(eml(1, eml(eml(1, x), 1))))
   #> log(x)
   ```
3. Points to vignettes for SR, master formula, bytecode internals.

### 6d. Vignettes (optional, time-permitting)

- `vignettes/intro.Rmd` — what is EML, what does the package do
- `vignettes/symbolic-regression.Rmd` — port the paper's Log_fit demo
- `vignettes/bytecode.Rmd` — internals for users who want to inspect

**Acceptance:** v1 test script passes unchanged on v2. Documentation
builds cleanly with `devtools::document()`.

---

## Total estimate: ~10 hours of focused implementation

Plus another 2-3 hours of debugging the simplifier (Phase 4 always takes
longer than estimated; pattern matchers are tricky).

## Order of operations

Phases 1-3 are mostly mechanical and can be done quickly. Phase 4 (simplifier)
is the conceptually hardest and is where the package's correctness lives —
budget extra time and be willing to discard a first attempt if pattern
matching gets tangled. Phase 5 is straightforward once Phase 4 works.
Phase 6 is polish.

If time-constrained, ship Phases 0-4 as v2.0.0 and Phase 5 as v2.1.0.
The simplifier alone is a substantial improvement over v1 and stands on
its own as a research tool.
