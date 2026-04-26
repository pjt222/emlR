# Test catalog

Specific test cases with expected values. Use these to write `testthat`
expectations directly. Numeric tolerances are 1e-8 unless stated otherwise.

---

## T1. Operator (`eml`)

| Input         | Expected                       | Notes |
|---------------|--------------------------------|-------|
| `eml(1, 1)`   | `exp(1) - log(1)` = e ≈ 2.718  | log(1) = 0 |
| `eml(0, 1)`   | `exp(0) - log(1)` = 1          |       |
| `eml(1, 0)`   | `Inf - (-Inf)` = +Inf          | extended reals |
| `eml(0, 0)`   | `1 - (-Inf)` = +Inf            |       |
| `eml(-Inf, e)`| `0 - 1` = -1                   | the trick for -1 |
| `eml(1i, 1)`  | `cos(1) + i*sin(1)`            | complex exp |
| `eml(0, -1)`  | `1 - i*pi`                     | principal branch of log(-1) |

---

## T2. Catalog identities (numeric values)

For each, evaluate at the given `vars` and check the value.

| Catalog name | Expression form                                | Vars         | Expected         |
|--------------|-----------------------------------------------|--------------|------------------|
| one          | `1`                                           | —            | 1                |
| e            | `eml(1, 1)`                                   | —            | exp(1)           |
| zero         | `eml(1, eml(eml(1, 1), 1))`                   | —            | 0                |
| neg_one      | (see canonical form in catalog)               | —            | -1               |
| two          | `tree_add(1, 1)`                              | —            | 2                |
| i            | (see catalog)                                 | —            | 0+1i             |
| pi           | (see catalog)                                 | —            | π ≈ 3.14159      |
| exp          | `eml(x, 1)`                                   | x = 0.5      | exp(0.5)         |
| log          | `eml(1, eml(eml(1, x), 1))`                   | x = 2        | log(2)           |
| minus        | (see catalog)                                 | x = 3        | -3               |
| add          | (see catalog)                                 | x=2, y=3     | 5                |
| sub          | (see catalog)                                 | x=5, y=2     | 3                |
| mul          | (see catalog)                                 | x=2, y=3     | 6                |
| div          | (see catalog)                                 | x=6, y=2     | 3                |
| pow          | (see catalog)                                 | x=2, y=3     | 8                |
| sqrt         | (see catalog)                                 | x = 16       | 4                |
| sin          | (see catalog)                                 | x = π/6      | 0.5              |
| cos          | (see catalog)                                 | x = π/3      | 0.5              |
| sin          | (see catalog)                                 | x = 0        | 0                |
| cos          | (see catalog)                                 | x = 0        | 1                |

For real-valued expected outputs, use `eml_eval(..., real = TRUE,
tol = 1e-8)`. The imag residue should be well below 1e-8 for all of
these — if it isn't, the principal-branch handling has a bug.

---

## T3. K (node count) and RPN

| Expression                            | Expected K | Expected RPN              |
|---------------------------------------|------------|---------------------------|
| `1`                                   | 1          | `"1"`                     |
| `quote(x)` (just a name)              | 1          | `"x"`                     |
| `quote(eml(x, 1))`                    | 3          | `"x 1 E"`                 |
| `quote(eml(1, 1))`                    | 3          | `"1 1 E"`                 |
| `quote(eml(1, eml(eml(1, x), 1)))`    | 7          | `"1 1 x E 1 E E"`         |

The K=7 case is the headline — that's the paper's example.

---

## T4. Depth

| Expression                            | Expected depth |
|---------------------------------------|----------------|
| `1`                                   | 0              |
| `quote(eml(x, 1))`                    | 1              |
| `quote(eml(1, eml(1, x)))`            | 2              |
| `quote(eml(1, eml(eml(1, x), 1)))`    | 3              |

---

## T5. Bytecode equivalence

Parameterised test: for every catalog entry `e`, for every `vars` table
in T2:

```r
v_eval <- eml_eval(e, vars)
v_bc   <- run_bytecode(compile_eml(e), vars)
expect_equal(v_eval, v_bc, tolerance = 1e-12)
```

Plus 100 random trees from a generator with depths 1-5 and 1-3 free
variables, evaluated on random complex vectors of length 1, 100, 10000.

---

## T6. Bytecode structure

For `quote(eml(1, eml(eml(1, x), 1)))`:

```r
bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
expect_equal(length(bc$ops), 7)            # 7 instructions
expect_equal(bc$consts, c(1+0i))            # one unique const
expect_equal(bc$vars, "x")                  # one variable
# Opcodes (LIT=0, VAR=1, EML=2):
#   LIT(1), LIT(1), VAR(x), EML, LIT(1), EML, EML
expect_equal(bc$ops, c(0L, 0L, 1L, 2L, 0L, 2L, 2L))
expect_equal(bc$args, c(1L, 1L, 1L, 0L, 1L, 0L, 0L))  # all LITs point to const idx 1
```

---

## T7. Pattern matcher (`match_eml`)

| expr                          | pattern                       | Expected                        |
|-------------------------------|-------------------------------|---------------------------------|
| `quote(eml(1, x))`            | `quote(eml(1, `_x`))`          | `list(`_x` = quote(x))`         |
| `quote(eml(1, x))`            | `quote(eml(`_x`, 1))`          | NULL                            |
| `quote(eml(x, x))`            | `quote(eml(`_x`, `_x`))`       | `list(`_x` = quote(x))`         |
| `quote(eml(x, y))`            | `quote(eml(`_x`, `_x`))`       | NULL (binding conflict)         |
| `1`                           | `1`                           | `list()` (matches with no bindings) |
| `quote(x)`                    | `quote(`_a`)`                  | `list(`_a` = quote(x))`         |
| `quote(eml(eml(1, x), 1))`    | `quote(eml(eml(1, `_a`), 1))`  | `list(`_a` = quote(x))`         |

---

## T8. Simplifier — single rules

| Input                                              | `simplify_native` output  | Rule |
|----------------------------------------------------|---------------------------|------|
| `quote(eml(x, 1))`                                 | `quote(exp(x))`           | N1   |
| `quote(eml(1, 1))`                                 | `exp(1)` numerically      | N2   |
| `quote(eml(1, eml(eml(1, x), 1)))`                 | `quote(log(x))`           | N3   |
| `quote(eml(log(a), exp(b)))`                       | `quote(a - b)`            | N4   |
| `quote(eml(log(x), 1))`                            | `quote(x)`                | N5   |

---

## T9. Simplifier — full catalog

For every entry in `eml_catalog()`:

```r
canon  <- catalog[[name]]
simp   <- simplify_native(canon)
expect_equal(deparse(simp), expected_native[[name]])
```

Where `expected_native` is the table from SPEC §5.2.

This is the package's single most important correctness test. If any
catalog entry doesn't simplify to its expected base-R form, either:
- the canonical EML construction is wrong, or
- a simplifier rule is missing, or
- a simplifier rule has a bug (most likely)

Use `simplify_native(canon, trace = TRUE)` to see which rules fire and
in what order. Compare to the expected derivation chain in the paper
(Fig. 1) or in `reference/emlR-v1/R/03_identities.R`.

---

## T10. Simplifier idempotence

For every catalog entry:

```r
once  <- simplify_native(catalog[[name]])
twice <- simplify_native(once)
expect_identical(once, twice)
```

A non-idempotent simplifier signals a non-confluent rule set. Don't
weaken the test — fix the rules.

---

## T11. Master formula structure

```r
expect_equal(master_n_params(1), 4)            # 5*2 - 6 = 4
expect_equal(master_n_params(2), 14)
expect_equal(master_n_params(3), 34)
expect_equal(master_n_params(4), 74)

m <- build_master(1)
# Should have 4 free symbols: alpha_1, beta_1, alpha_2, beta_2
expect_setequal(all.vars(m),
                c("x", "alpha_1", "beta_1", "alpha_2", "beta_2"))
```

---

## T12. Master formula selectors

```r
# Selector for exp(x) at depth 1
par_exp <- selector_for_exp()      # returns named list of param values
expr <- build_master(1)
val <- eml_eval(expr, c(par_exp, list(x = 2)))
expect_equal(Re(val), exp(2), tolerance = 1e-10)

# Selector for log(x) at depth 3 (paper Eq. 5 wired into master)
par_log <- selector_for_log()
expr <- build_master(3)
val <- eml_eval(expr, c(par_log, list(x = 5)))
expect_equal(Re(val), log(5), tolerance = 1e-10)
```

---

## T13. Gradient correctness

For a depth-2 master formula at random parameter values:

```r
expr <- build_master(2)
par  <- runif(master_n_params(2), -1, 1)
xs   <- runif(20, 0.5, 5)

# Analytic gradient via Deriv
g_analytic <- compute_master_gradient(expr, par, xs)

# Numerical gradient via finite differences
eps <- 1e-6
g_numeric <- numeric(length(par))
for (i in seq_along(par)) {
  par_p <- par; par_p[i] <- par_p[i] + eps
  par_m <- par; par_m[i] <- par_m[i] - eps
  loss_p <- mean((Re(eml_eval(expr, c(unpack_master_params(par_p, 2),
                                      list(x = xs)))) - log(xs))^2)
  loss_m <- mean((Re(eml_eval(expr, c(unpack_master_params(par_m, 2),
                                      list(x = xs)))) - log(xs))^2)
  g_numeric[i] <- (loss_p - loss_m) / (2 * eps)
}

expect_equal(g_analytic, g_numeric, tolerance = 1e-5)
```

---

## T14. SR recovery of log(x)

The paper's headline demo. Run with multiple seeds:

```r
xs <- seq(0.5, 5, length.out = 30)
ys <- log(xs)

successes <- 0
for (seed in 1:10) {
  fit <- eml_fit(xs, ys, depth = 3, parameterization = "simplex",
                 method = "L-BFGS-B", maxit = 1000, n_restarts = 1,
                 seed = seed)
  if (fit$snap_mse < 1e-20) successes <- successes + 1
}

# Paper reports ~25% success rate at depth 3 from random init.
# With L-BFGS-B and analytic gradients, expect at least 30%.
expect_gte(successes, 3)

# With n_restarts = 10, expect at least 8/10 runs to succeed.
fit_robust <- eml_fit(xs, ys, depth = 3, n_restarts = 10, seed = 42)
expect_lt(fit_robust$snap_mse, 1e-20)
```

The `n_restarts = 10` test is the production check. The single-restart
test is informational and may be flaky on different hardware/RNG.

---

## T15. v1 compatibility

Run the unmodified `reference/emlR-v1/tests/test_eml.R` against v2 with
the compat shim loaded. All assertions must pass. The script's `eml_K`
calls will return different numeric values (paper-K vs leaf-K); fix
either:
- update the v1 script to use `eml_leafcount` for the old behaviour, or
- accept that v1 tests fail on K and document the change in NEWS.md.

Prefer the second approach: the v1 K was wrong, document the correction.

---

## How to run

```r
# From package root
devtools::test()                    # all tests
devtools::test_active_file()        # current file only

# Or from the command line
R CMD check --as-cran .
```

CI is out of scope for v2.0.0 but a `.github/workflows/R-CMD-check.yaml`
following the standard r-lib template would be appropriate later.
