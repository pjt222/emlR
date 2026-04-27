# =============================================================================
#  Catalog tests: numeric verification, structural simplification (§5.2),
#  and idempotence (§3.5 / T10).
# =============================================================================

test_that("eml_catalog() exposes all expected primitives", {
  catalog <- eml_catalog()
  expected <- c("one", "e", "zero", "neg_one", "two", "i", "pi",
                "exp", "log", "minus",
                "add", "sub", "mul", "div", "pow", "sqrt",
                "sin", "cos")
  expect_setequal(names(catalog), expected)
  for (nm in names(catalog)) {
    expect_true(is_eml_expr(catalog[[nm]]),
                info = sprintf("catalog$%s is not an EML expression", nm))
  }
})

test_that("verify_catalog returns TRUE — every entry numerically correct", {
  expect_true(verify_catalog(verbose = FALSE))
})

# --- 4d/T10: idempotence on every catalog entry -----------------------------

test_that("simplify_native is idempotent on every catalog entry", {
  catalog <- eml_catalog()
  for (nm in names(catalog)) {
    once  <- simplify_native(catalog[[nm]])
    twice <- simplify_native(once)
    expect_identical(once, twice,
                     info = sprintf("non-idempotent on catalog$%s", nm))
  }
})

# --- 4e/T9: §5.2 structural-form check ---------------------------------------
#
# Every catalog entry must collapse to the structural form documented
# in SPEC §5.2. The Euler entries (sin, cos) and sqrt rely on the
# C-exp-const-plus-log cleanup rule + tolerance-aware atomic equality
# to bridge round-off in tree_i() = exp(log(-1)/2).

# Helper: structural equality after deparse normalisation.
.deparse_norm <- function(e) {
  paste(deparse(e, width.cutoff = 500L), collapse = " ")
}

test_that("simplify_native reaches the SPEC §5.2 structural form", {
  expectations <- list(
    one     = "1",
    exp     = "exp(x)",
    log     = "log(x)",
    sub     = "x - y",
    minus   = "-x",
    add     = "x + y",
    mul     = "x * y",
    div     = "x/y",
    pow     = "x^y",
    sqrt    = "x^0.5",
    sin     = "sin(x)",
    cos     = "cos(x)"
  )
  catalog <- eml_catalog()
  for (nm in names(expectations)) {
    out <- simplify_native(catalog[[nm]])
    expect_identical(.deparse_norm(out), expectations[[nm]],
                     info = sprintf("structural form mismatch: %s", nm))
  }
})

test_that("constants (e, zero, neg_one, two, i, pi) fold to their values", {
  vals <- list(
    e       = exp(1),
    zero    = 0,
    neg_one = -1,
    two     = 2,
    i       = 1i,
    pi      = pi
  )
  catalog <- eml_catalog()
  for (nm in names(vals)) {
    out <- simplify_native(catalog[[nm]])
    expect_true(is.numeric(out) || is.complex(out),
                info = sprintf("%s did not fold to a literal", nm))
    expect_equal(as.complex(out), as.complex(vals[[nm]]),
                 tolerance = 1e-12,
                 info = sprintf("%s folded value mismatch", nm))
  }
})

test_that("simplified sqrt, sin, cos still evaluate correctly", {
  # Belt-and-braces: structural form is checked above; this verifies
  # the symbolic output also evaluates to the right numeric value.
  spec_pts <- list(
    sqrt = list(x = 16,        expected = 4),
    sin  = list(x = pi / 6,    expected = 0.5),
    cos  = list(x = pi / 3,    expected = 0.5)
  )
  catalog <- eml_catalog()
  for (nm in names(spec_pts)) {
    s <- simplify_native(catalog[[nm]])
    val <- eval(s, list2env(spec_pts[[nm]][names(spec_pts[[nm]]) != "expected"],
                            parent = baseenv()))
    expect_equal(Re(as.complex(val)), spec_pts[[nm]]$expected,
                 tolerance = 1e-8,
                 info = sprintf("simplified %s evaluates wrong", nm))
  }
})

# --- 4f/F4: numeric eval-equivalence sweep ----------------------------------
#
# The structural test above compares deparse strings, which catches a
# wrong head/shape but is silent on a wrong constant (e.g. exp(2) where
# exp(1) is expected). This sweeps each catalog entry over multiple
# numeric points and compares eml_eval(orig) against
# eval(simplify_native(orig)) under the same bindings. A bug that
# rewrites the tree to a structurally-correct but numerically-wrong
# form (e.g. swapping a sub-tree for `e` instead of `1`) would survive
# the deparse test but fail here.
#
# Bindings are chosen for principal-branch safety: log/sqrt domain
# starts at >= 0, division avoids y = 0, pow uses x > 0.

test_that("simplify_native preserves numeric value across the catalog", {
  sweep_pts <- list(
    one     = list(list()),
    e       = list(list()),
    zero    = list(list()),
    neg_one = list(list()),
    two     = list(list()),
    i       = list(list()),
    pi      = list(list()),
    exp     = lapply(c(-1, 0, 0.5, 1, 2),       function(v) list(x = v)),
    log     = lapply(c(0.25, 0.5, 1, 2, 5, 10), function(v) list(x = v)),
    minus   = lapply(c(-3, -0.5, 0, 0.5, 3),    function(v) list(x = v)),
    add     = list(list(x = 2,  y = 3),  list(x = -1, y = 4),
                   list(x = 0,  y = 0),  list(x = 0.25, y = 0.75)),
    sub     = list(list(x = 5,  y = 2),  list(x = -1, y = 4),
                   list(x = 0,  y = 0),  list(x = 1.5,  y = 0.5)),
    mul     = list(list(x = 2,  y = 3),  list(x = -1, y = 4),
                   list(x = 0,  y = 5),  list(x = 0.5,  y = -2)),
    div     = list(list(x = 6,  y = 2),  list(x = 1,  y = 4),
                   list(x = -3, y = 0.5), list(x = 0,    y = 7)),
    pow     = list(list(x = 2,  y = 3),  list(x = 0.5, y = 2),
                   list(x = 4,  y = 0.5), list(x = 1.5,  y = -1)),
    sqrt    = lapply(c(0.25, 1, 4, 16, 100),    function(v) list(x = v)),
    sin     = lapply(c(0, pi / 6, pi / 4, pi / 3, pi / 2, pi),
                     function(v) list(x = v)),
    cos     = lapply(c(0, pi / 6, pi / 4, pi / 3, pi / 2, pi),
                     function(v) list(x = v))
  )

  catalog <- eml_catalog()
  for (nm in names(catalog)) {
    expr <- catalog[[nm]]
    s    <- simplify_native(expr)
    for (vars in sweep_pts[[nm]]) {
      val_eml  <- eml_eval(expr, vars)
      env      <- list2env(vars, parent = baseenv())
      val_simp <- as.complex(eval(s, env))
      expect_equal(
        as.complex(val_simp), as.complex(val_eml),
        tolerance = 1e-8,
        info = sprintf("%s mismatch at vars=%s",
                       nm, paste(names(vars), unlist(vars),
                                 sep = "=", collapse = ","))
      )
    }
  }
})

# --- 4e: the package's headline correctness check ---------------------------

test_that("HEADLINE: simplify_native(tree_ln('x')) is quote(log(x)) literally", {
  expect_identical(simplify_native(tree_ln("x")), quote(log(x)))
  # Equivalent constructions
  expect_identical(simplify_native(tree_log("x")),  quote(log(x)))
  expect_identical(simplify_native(quote(eml(1, eml(eml(1, x), 1)))),
                   quote(log(x)))
})
