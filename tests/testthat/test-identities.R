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

# --- 4e/T9: §5.2 structural-form check, with documented allowlist -----------
#
# Entries that reach the structural form expected by SPEC §5.2 via the
# rule set N1-N7 + cleanup. The remaining catalog entries (sqrt, sin,
# cos) evaluate to the correct value but do not collapse to their
# base-R structural form with the current rule set; SPEC §5.3 flags
# the Euler-rule cleanup as "arguably outside the simplifier's remit".
# These are covered by the numeric `verify_catalog` test above.

# Helper: structural equality after deparse normalisation.
.deparse_norm <- function(e) {
  paste(deparse(e, width.cutoff = 500L), collapse = " ")
}

test_that("simplify_native reaches the SPEC §5.2 structural form (subset)", {
  expectations <- list(
    one     = "1",
    exp     = "exp(x)",
    log     = "log(x)",
    sub     = "x - y",
    minus   = "-x",
    add     = "x + y",
    mul     = "x * y",
    div     = "x/y",
    pow     = "x^y"
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

test_that("sqrt, sin, cos evaluate correctly even if not structurally collapsed", {
  # Spec §5.3: Euler simplification is optional; these entries are
  # guaranteed numerically correct (verify_catalog) but may retain
  # extra structure under the current rule set.
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

# --- 4e: the package's headline correctness check ---------------------------

test_that("HEADLINE: simplify_native(tree_ln('x')) is quote(log(x)) literally", {
  expect_identical(simplify_native(tree_ln("x")), quote(log(x)))
  # Equivalent constructions
  expect_identical(simplify_native(tree_log("x")),  quote(log(x)))
  expect_identical(simplify_native(quote(eml(1, eml(eml(1, x), 1)))),
                   quote(log(x)))
})
