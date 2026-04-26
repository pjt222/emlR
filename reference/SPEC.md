# emlR2 — Technical Specification

**Status:** design, ready for implementation
**Target R version:** ≥ 4.1 (for native pipe; otherwise ≥ 3.6)
**Dependencies:** base R, `Deriv` (CRAN, MIT license)
**Reference:** Odrzywołek (2026), arXiv:2603.21852

This document specifies the v2 architecture. It is normative: deviations
from this spec require justification in `NEWS.md` or an ADR.

---

## 1. Representation: EML expressions are R calls

The single AST is the R AST. An EML expression is one of:

| Form                          | R type                | Example              |
| ----------------------------- | --------------------- | -------------------- |
| numeric or complex literal    | atomic length-1       | `1`, `-1+0i`         |
| variable reference            | `name` (a.k.a symbol) | `as.name("x")`       |
| EML node                      | `call`                | `call("eml", l, r)`  |

There is **no** `eml_tree` S3 class. The class of an EML expression is
whatever R says it is (`numeric`, `complex`, `name`, `call`). Every
function in the package that takes "an EML expression" accepts any of
these and dispatches with `is.numeric() / is.complex() / is.name() /
is.call()` checks (or uses `switch(typeof(x), ...)` where appropriate).

### Rationale

This is the entire point of v2. The v1 `eml_tree` S3 class re-implemented,
poorly, what `call` already does for free:

- `deparse(expr)` already produces the textual form
- `bquote(eml(.(l), .(r)))` already substitutes
- `all.vars(expr)` already enumerates free variables
- `Deriv::Deriv(expr, "x")` already differentiates symbolically
- `eval(expr, list(x = 5, eml = eml))` already evaluates

### Constructors

```r
eml_const(v)         # returns v unchanged if numeric/complex
eml_var(name)        # as.name(name); accepts string or already-name
eml_node(l, r)       # call("eml", l, r) after coercing children
                     # via as_eml_expr()
as_eml_expr(x)       # accepts numeric -> stays; character -> as.name;
                     # call/name -> stays; otherwise stop()
E(l, r)              # alias for eml_node, kept for ergonomics
```

### Predicates

```r
is_eml_expr(x)       # TRUE for numeric/complex/name/call("eml",...)
is_eml_call(x)       # TRUE only for call("eml", l, r)
is_eml_const(x)      # TRUE for numeric/complex literal
is_eml_var(x)        # TRUE for name
```

---

## 2. Evaluation

### 2.1 The operator

`eml(x, y) = exp(as.complex(x)) - log(as.complex(y))`

Identical to v1. Always coerces to complex, returns complex. This is the
only function that needs to know the principal-branch convention; everything
else inherits it.

A real wrapper `eml_real(x, y, tol = 1e-9)` returns `Re(z)` after checking
that `|Im(z)| < tol`; warns otherwise.

### 2.2 Tree evaluation by `eval()`

```r
eml_eval(expr, vars = list(), real = FALSE, tol = 1e-8)
```

Internally this builds an environment `env <- list2env(c(list(eml = eml),
vars))` and calls `eval(expr, env)`. Returns complex unless `real = TRUE`
in which case it returns `Re(eval(expr, env))` after the imag-residue check.

Vectorised input values are supported: if `vars$x` is a numeric vector,
the result is a complex vector of the same length, by virtue of `exp` and
`log` being vectorised.

### 2.3 Tree evaluation by bytecode (fast path)

See §4. Same semantics as `eml_eval()` but typically 10-100× faster for
deep trees evaluated on long input vectors. The bytecode evaluator is
the primary engine for SR training inner loops.

---

## 3. Simplifier

The simplifier is a tree rewriter. It accepts an EML expression and returns
an equivalent expression, where "equivalent" means: produces the same value
on the principal branch for every input on which both sides are defined.

### 3.1 Two modes

**`simplify_eml(expr)`** — stays inside the EML grammar. Useful for
inspecting trees, computing K (leaf count), and as a normalisation step
before bytecode compilation. Idempotent: `simplify_eml(simplify_eml(x))`
is identical to `simplify_eml(x)`.

**`simplify_native(expr)`** — collapses recognised EML patterns to their
base-R counterparts. Output may contain `exp`, `log`, `+`, `-`, `*`, `/`,
`^`, `sin`, `cos`, etc. — anything `eval()` can handle. This is the
"fast" mode and produces expressions you can inspect to verify the v1
constructions are correct (the headline test: `simplify_native` of
`tree_ln("x")` should produce `log(x)` literally).

### 3.2 Rewrite rules — `simplify_eml`

Applied bottom-up, repeatedly to a fixed point.

| Rule | Pattern                              | Result           | Justification |
|------|--------------------------------------|------------------|---------------|
| C1   | constant subtree (no free vars)      | folded to value  | trivial       |
| C2   | `eml(a, b)` with both numeric        | `eml(a, b)` value| C1 special    |
| L1   | `eml(x, 1)`                          | unchanged in EML mode | preserve grammar |
| L2   | `eml(1, eml(eml(1, x), 1))`          | unchanged        | preserve grammar |

In EML mode the only safe simplification is constant folding. We do not
re-write `eml` calls because the master formula's completeness depends on
preserving them.

### 3.3 Rewrite rules — `simplify_native`

Applied bottom-up, repeatedly to a fixed point. Each rule is a pattern
match on `call` objects. Patterns use a meta-syntax: `_x` matches anything,
`_n` matches a literal number, identical-named meta-vars must bind to
identical sub-expressions.

| Rule | Pattern                              | Result          | Notes |
|------|--------------------------------------|-----------------|-------|
| N1   | `eml(_x, 1)`                         | `exp(_x)`       | paper, §1 |
| N2   | `eml(1, 1)`                          | `exp(1)`        | = e, paper |
| N3   | `eml(1, eml(eml(1, _x), 1))`         | `log(_x)`       | paper Eq. 5 |
| N4   | `eml(log(_x), exp(_y))`              | `_x - _y`       | direct from defn |
| N5   | `eml(log(_x), 1)`                    | `_x`            | = exp(log(x)) - log(1) = x |
| N6   | `eml(0, _y)`                         | `1 - log(_y)`   | constant simplify |
| N7   | `eml(_x, exp(_y))`                   | `exp(_x) - _y`  | symmetric to N4 |
| C1   | constant fold                        | numeric value   | post-simplification |

After applying these, run constant folding once more. Idempotence: prove
by case analysis that no rule produces a pattern matchable by any other
rule applied to its sub-expressions.

**Open question for the implementer:** N4 and N7 overlap when both `_x =
log(...)` and `_y` is wrapped in `exp(...)`. Choose N4 (preferred form
gets subtraction directly). Document the choice in the simplifier source.

### 3.4 Pattern matching primitive

```r
match_eml(expr, pattern)
# pattern is an EML expression where unbound names starting with "_"
# are meta-variables. Returns NULL on no match, or a named list of
# bindings on match.
```

Implementation hint: walk both `expr` and `pattern` in parallel. When
`pattern` is a name starting with "_", record/check binding. When both
are calls, recurse on `[[1]], [[2]], [[3]]`. When both are atomic, check
`identical()`.

### 3.5 Idempotence test

For every expression `e` produced by the catalog (§5.1):

```r
once  <- simplify_native(e)
twice <- simplify_native(once)
stopifnot(identical(once, twice))
```

Failure indicates a non-confluent rule set; debug by enabling rule-trace
mode (see §3.6).

### 3.6 Rule-trace mode

`simplify_native(expr, trace = TRUE)` returns a list with components
`result`, `rules` (a character vector of rule names applied in order),
and `intermediates` (a list of expressions after each rule firing).
For debugging only — not used in hot paths.

---

## 4. Bytecode compiler and evaluator

### 4.1 Instruction set

Stack machine. Three instructions:

| Opcode | Mnemonic | Stack effect            | Argument            |
|--------|----------|-------------------------|---------------------|
| 0      | `LIT`    | `... → ..., v`          | constant index `i`  |
| 1      | `VAR`    | `... → ..., x_j`        | variable index `j`  |
| 2      | `EML`    | `..., a, b → ..., eml(a, b)` | none           |

That's it. The grammar `S → 1 | x | eml(S, S)` maps directly to this ISA;
the paper's Sect. 4.1 describes the same machine ("a single instruction
stack machine, closely resembling a single-button RPN calculator").

### 4.2 Compiled form

```r
compile_eml(expr) -> list(
  ops      = integer vector,        # opcodes
  args     = integer vector,        # opcode arguments (0 for EML)
  consts   = complex vector,        # constants pool, 1-indexed
  vars     = character vector,      # variable names, 1-indexed
  source   = expr                   # original expression for inspection
)
```

Compilation is a post-order walk that emits `LIT` / `VAR` / `EML` and
deduplicates the constants pool.

### 4.3 Evaluator

```r
run_bytecode(bc, vars = list()) -> complex vector
```

Pseudocode:

```
stack <- vector(mode = "complex", length = max_stack_depth)  # preallocated
sp <- 0
for k in seq_along(bc$ops):
  switch(bc$ops[k]):
    LIT: sp <- sp + 1; stack[sp] <- bc$consts[bc$args[k]]
    VAR: sp <- sp + 1; stack[sp] <- vars[[bc$vars[bc$args[k]]]]
    EML: sp <- sp - 1; stack[sp] <- exp(stack[sp]) - log(stack[sp + 1])
return(stack[1])
```

Crucially, when `vars[[name]]` is a numeric vector of length N, every
`stack[sp]` slot is itself a vector of length N. The `exp` and `log`
calls vectorise. Result is a vector of length N. This is the speedup:
one tight loop in R-byte-compiled R, hitting BLAS-friendly `exp`/`log`
once per node, no recursion, no S3 dispatch.

### 4.4 Stack depth analysis

Compute `max_stack_depth` at compile time by walking the bytecode:
`LIT`/`VAR` → +1, `EML` → -1, take running max. Preallocate the stack.
A balanced depth-d EML tree needs stack depth `d + 1`.

### 4.5 Equivalence test (mandatory)

For 100 random EML trees of varying depths, on 100 random input vectors:

```r
v_ref <- eml_eval(expr, vars)
v_bc  <- run_bytecode(compile_eml(expr), vars)
stopifnot(all.equal(v_ref, v_bc, tolerance = 1e-12))
```

If this fails, the bytecode compiler or evaluator is wrong. Investigate
before optimising further.

---

## 5. Identity catalog

### 5.1 Canonical forms

The catalog provides EML expressions for all primitives in the paper's
Table 1. The v1 constructions in `reference/emlR-v1/R/03_identities.R` are
correct and should be ported verbatim, with only the AST representation
change (custom list → `call`).

```r
eml_catalog() -> list(
  e       = quote(eml(1, 1)),
  exp     = quote(eml(x, 1)),                         # paper, K=3
  log     = quote(eml(1, eml(eml(1, x), 1))),         # paper Eq. 5, K=7
  zero    = quote(eml(1, eml(eml(1, 1), 1))),         # = log(1)
  neg_one = quote(eml(eml(1, eml(eml(1, eml(1, eml(eml(1, 1), 1))), 1)),
                       eml(1, 1))),                   # via -1 = sub(0, 1)
  ...
)
```

Each entry is the v1 construction expressed as an R `call`. The leaf-count
`K` of each must match the v1 K (it should, since the structures are
identical).

### 5.2 Verification

For every catalog entry `e`:

```r
v_canon  <- e
v_simp   <- simplify_native(v_canon)
v_native <- expected_native_form(name)  # e.g. quote(log(x)) for "log"
stopifnot(identical(v_simp, v_native))
```

Where the expected native form is:

| Catalog name | Expected `simplify_native` output    |
| ------------ | ------------------------------------ |
| e            | `exp(1)` or numeric `2.718...`       |
| exp          | `exp(x)`                             |
| log          | `log(x)`                             |
| zero         | numeric `0`                          |
| neg_one      | numeric `-1`                         |
| add          | `x + y`                              |
| sub          | `x - y`                              |
| mul          | `x * y`                              |
| div          | `x / y`                              |
| pow          | `x ^ y`                              |
| sqrt         | `sqrt(x)` or `x ^ 0.5`               |
| sin          | `sin(x)` (after Euler simplification, see §5.3) |
| cos          | `cos(x)` (after Euler simplification, see §5.3) |
| pi           | numeric `3.14159...`                 |
| i            | complex `0+1i`                       |
| two          | numeric `2`                          |

This is the strongest correctness check the package has. If any of these
fail, either the canonical form is wrong or the simplifier is missing a
rule. **Both should be fixed; do not weaken the test.**

### 5.3 Euler-formula simplification (sin, cos)

`sin(x)` is constructed as `(exp(i*x) - exp(-i*x)) / (2i)`. After
`simplify_native` collapses the EML nodes, you have an expression in
terms of `exp`, `i`, and `x`. To recognise this as `sin(x)`, the
simplifier needs an extra rule:

| Rule | Pattern                                            | Result    |
|------|----------------------------------------------------|-----------|
| E1   | `(exp(0+1i * _x) - exp(-(0+1i * _x))) / (0+2i)`    | `sin(_x)` |
| E2   | `(exp(0+1i * _x) + exp(-(0+1i * _x))) / 2`         | `cos(_x)` |

These are arguably outside the simplifier's remit (they're trig identities,
not EML rewrites) but including them gives the catalog test §5.2 a clean
pass for sin/cos. Mark these as a separate rule group `simplify_native(expr,
include_euler = TRUE)`, default TRUE.

---

## 6. Master formula and SR training

### 6.1 Master formula construction

```r
build_master(depth, var_name = "x") -> expr
```

Returns an R `call` expression representing the depth-n master formula.
At each input slot, the contribution is

  `α_i * 1 + β_i * x + γ_i * f`

where parameters are encoded as named symbols `alpha_<slot>`, `beta_<slot>`,
`gamma_<slot>`. The expression is then a call tree of `eml` nodes
parameterised by these symbols.

Example (depth 1):

```r
build_master(1)
#> eml(alpha_1 * 1 + beta_1 * x,
#>     alpha_2 * 1 + beta_2 * x)
```

Slot count and parameter count match the paper:
- slots: `2^(depth+1) - 2`
- parameters at leaf slots: 2 (α, β)
- parameters at inner slots: 3 (α, β, γ)
- total parameters: `5 * 2^depth - 6`

### 6.2 Parameterisation

Two modes:

**Direct.** Parameters are passed as a flat numeric vector of length
`5 * 2^depth - 6`. The mapping from vector index to (slot, param) is
documented and stable. Helper `unpack_master_params(par, depth)` returns
a named list keyed by the symbol names (`alpha_1`, `beta_1`, ...).

**Simplex (softmax).** Parameters are logits; per-slot triples (or pairs at
leaves) are pushed through softmax to produce non-negative weights summing
to 1. This is the parameterisation used in the paper's Sect. 4.3 for
recovery of exact closed forms — at the optimum, weights snap to one-hot
vertices corresponding to grammar choices `1`, `x`, or `f`.

The choice is controlled by the `parameterization` argument to `eml_fit`.

### 6.3 Symbolic gradients via Deriv

For a depth-n master formula `expr` and a parameter vector `par`:

1. Substitute current parameter values into `expr` to get a residual
   expression in `x` only — but **do not** do this for gradient
   computation. Keep parameters symbolic.
2. For each parameter symbol `p`, compute `Deriv::Deriv(expr, p)`. This
   returns an R expression for `∂expr/∂p`.
3. At call time, evaluate each gradient expression at the current `par`
   and `x` data. The result is a Jacobian column.

`Deriv` knows `exp`, `log`, `+`, `-`, `*`, `/`, `^`. It does not know `eml`
out of the box. Two solutions:

**Option A (preferred):** Before differentiating, expand every `eml(a, b)`
in the master formula to `exp(a) - log(b)`. This is a one-line substitution
on the call tree. `Deriv` then handles the expanded form natively.

**Option B:** Register `eml` as a known function with `Deriv`:

```r
Deriv::drule[["eml"]] <- alist(x = exp(x), y = -1/y)
```

This tells `Deriv` that `∂eml(x,y)/∂x = exp(x)` and `∂eml(x,y)/∂y = -1/y`.
Cleaner, but requires touching `Deriv`'s registry.

Choose Option A for portability. Document Option B in a comment for users
who want to register `eml` globally.

### 6.4 Loss and optimisation

```r
eml_fit(x, y, depth = 3, parameterization = "simplex",
        method = "L-BFGS-B", maxit = 1000, seed = 42) -> list
```

Loss is MSE on the real part:

```r
loss(par) {
  pred <- run_bytecode(bc_with_params_substituted(par), list(x = x))
  mean((Re(pred) - y)^2)
}
```

Gradient is the symbolic chain through `Deriv`, evaluated at `par` and `x`,
summed over data points. This is the speedup: gradients are analytic, so
`L-BFGS-B` works directly. The v1 SANN fitter is replaced.

### 6.5 Snapping

After convergence, snap each (α, β, γ) triple to its argmax one-hot vertex.
Re-evaluate. If snapped MSE is at machine epsilon squared (~1e-32), the
SR has recovered an exact closed form.

```r
snap_master_params(par, depth) -> par_snapped
```

### 6.6 Multi-restart

Per the paper's Sect. 4.3, depth-3 recovery succeeds in ~25% of random
inits. The fitter should accept `n_restarts` and return the best result.
Default 1; set to 10-20 for production SR.

---

## 7. API surface

Public functions exported by the package:

```
# Core
eml(x, y)                       # the operator
eml_real(x, y, tol)             # real-projection wrapper

# Construction
eml_const(v)
eml_var(name)
eml_node(l, r)
E(l, r)                         # alias
as_eml_expr(x)

# Predicates
is_eml_expr(x)
is_eml_call(x)
is_eml_const(x)
is_eml_var(x)

# Inspection
eml_K(expr)                     # leaf count
eml_depth(expr)                 # tree depth
eml_rpn(expr)                   # RPN string
print(<call>)                   # uses default deparse, no S3 method needed

# Evaluation
eml_eval(expr, vars, real, tol)
compile_eml(expr)
run_bytecode(bc, vars)

# Simplification
simplify_eml(expr)
simplify_native(expr, include_euler, trace)
match_eml(expr, pattern)        # exposed for advanced users

# Catalog
eml_catalog()
verify_catalog()                # runs §5.2 self-test

# Identities (return calls, not eml_tree)
tree_e()
tree_exp(x)
tree_ln(x)                      # name kept for v1 compat; accepts expr or name
tree_zero()
tree_neg_one()
tree_two()
tree_i()
tree_pi()
tree_minus(x)
tree_add(x, y)
tree_sub(x, y)
tree_mul(x, y)
tree_div(x, y)
tree_pow(x, y)
tree_sqrt(x)
tree_sin(x)
tree_cos(x)

# Master formula and SR
build_master(depth, var_name)
master_n_params(depth)
unpack_master_params(par, depth)
snap_master_params(par, depth)
eml_fit(x, y, depth, parameterization, method, maxit, n_restarts, seed)
```

---

## 8. Performance targets

These are *targets*, not requirements. Failure to meet them is a signal
to investigate, not necessarily a blocker.

| Operation                                    | v1 baseline | v2 target |
|----------------------------------------------|-------------|-----------|
| Evaluate K=7 ln tree at 1 point              | ~50µs       | ~20µs     |
| Evaluate K=7 ln tree at 10⁴ points (vec)     | ~500ms      | ~5ms      |
| `simplify_native(tree_log("x"))` → `log(x)`  | N/A         | ~1ms      |
| `eml_fit(depth=3)` on 30 points              | ~30s (SANN) | <1s (LBFGS) |
| 100 random tree equiv test (§4.5)            | N/A         | <5s       |

The vectorised bytecode evaluator should give 50-100× speedup on long input
vectors compared to the v1 recursive evaluator. If it doesn't, the
preallocation or stack-management path is wrong.

---

## 9. Compatibility with v1

A shim file `compat_v1.R` provides:

- `eml_tree` constructor that returns a `call` (deprecated, warns on use)
- `eml_eval(<eml_tree>, vars)` that handles both v1 lists and v2 calls

The v1 test script `reference/emlR-v1/tests/test_eml.R` should pass on v2
unmodified, modulo two changes:
- v1 `format.eml_tree(x)` becomes `deparse(x)`
- v1 `eml_K(<list>)` becomes `eml_K(<call>)` — same function name, different
  argument type.

Ship the compat shim. Plan to retire it after one minor version.

---

## 10. Out of scope (for v2)

- Multivariate input variables beyond two. The infrastructure should not
  preclude `x, y, z, ...` but only two-var cases need to be tested.
- The EDL (`exp(x)/log(y)`) and `−eml(y,x)` variants from Eq. (4b/4c).
  Add `edl()` and friends if needed in v3.
- Complex-output graphics or Tone.js-style audio output (you have other
  projects for that).
- Rcpp / `torch` integration. v3 candidates if profiling shows the
  bytecode evaluator is the new bottleneck.
- Symbolic regression search over tree topology (genetic programming
  style). The master-formula approach is sufficient for the paper's
  reproducibility goal.
