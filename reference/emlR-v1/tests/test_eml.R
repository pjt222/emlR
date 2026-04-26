# =============================================================================
#  emlR test script
#
#  Verifies every identity in the catalog and runs the symbolic regression
#  demo for ln(x).  Run with:
#      Rscript tests/test_eml.R
# =============================================================================

# Source the package
src_dir <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), ".."))
for (f in list.files(file.path(src_dir, "R"), full.names = TRUE, pattern = "\\.R$")) {
  source(f)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("================================================================\n")
cat(" emlR -- testing identities from Odrzywolek (2026), arXiv:2603.21852\n")
cat("================================================================\n\n")

# Tolerance for floating point comparisons
TOL <- 1e-8

# --- 1. Constants ------------------------------------------------------------

check <- function(name, tree, expected, vars = list()) {
  got <- eml_eval(tree, vars)
  ok <- isTRUE(all.equal(as.complex(got), as.complex(expected),
                          tolerance = TOL, check.attributes = FALSE))
  status <- if (ok) "OK " else "FAIL"
  cat(sprintf("  [%s] %-12s K=%-3d  got = %s  expected = %s\n",
              status, name, eml_K(tree),
              format(round(got, 6)), format(round(expected, 6))))
  ok
}

cat("--- Constants ---\n")
check("1",       tree_one(),      1)
check("e",       tree_e(),        exp(1))
check("0",       tree_zero(),     0)
check("-1",      tree_neg_one(),  -1)
check("2",       tree_two(),      2)
check("i",       tree_i(),        1i)
check("pi",      tree_pi(),       pi)
cat("\n")

# --- 2. Univariate functions -------------------------------------------------

cat("--- Univariate functions (test points) ---\n")

xs <- c(0.5, 1.0, 1.5, 2.0, 3.0)
for (x in xs) {
  cat(sprintf(" x = %.2f\n", x))
  check("exp(x)",   tree_exp("x"),   exp(x),     list(x = x))
  check("ln(x)",    tree_ln("x"),    log(x),     list(x = x))
  check("-x",       tree_minus("x"), -x,         list(x = x))
  check("sqrt(x)",  tree_sqrt("x"),  sqrt(x),    list(x = x))
  check("sin(x)",   tree_sin("x"),   sin(x),     list(x = x))
  check("cos(x)",   tree_cos("x"),   cos(x),     list(x = x))
}
cat("\n")

# --- 3. Bivariate operations -------------------------------------------------

cat("--- Bivariate operations (x = 2.5, y = 1.7) ---\n")
vars <- list(x = 2.5, y = 1.7)
check("x + y", tree_add("x", "y"), 2.5 + 1.7, vars)
check("x - y", tree_sub("x", "y"), 2.5 - 1.7, vars)
check("x * y", tree_mul("x", "y"), 2.5 * 1.7, vars)
check("x / y", tree_div("x", "y"), 2.5 / 1.7, vars)
check("x ^ y", tree_pow("x", "y"), 2.5 ^ 1.7, vars)
cat("\n")

# --- 4. Show RPN serialization for ln(x) (paper's K=7 form) ------------------

cat("--- RPN serialization (paper Eq. 5: ln(x)) ---\n")
ln_tree <- tree_ln("x")
cat("  Pretty form: ", format(ln_tree), "\n", sep = "")
cat("  RPN form:    ", eml_rpn(ln_tree), "\n", sep = "")
cat("  Leaf count K = ", eml_K(ln_tree), " (paper: 7)\n", sep = "")
cat("\n")

# --- 5. Master formula sanity check ------------------------------------------

cat("--- Master formula: depth-1 selector for exp(x) ---\n")
xs <- seq(-1, 1, length.out = 5)
exp_pred <- Re(eml_master_eval(1, xs, theta_for_exp()))
cat("  x:        ", paste(round(xs, 3), collapse = ", "), "\n")
cat("  predicted:", paste(round(exp_pred, 5), collapse = ", "), "\n")
cat("  exp(x):   ", paste(round(exp(xs), 5), collapse = ", "), "\n")
cat("  max err:  ", max(abs(exp_pred - exp(xs))), "\n\n")

# --- 6. Symbolic regression demo: recover ln(x) ------------------------------

cat("--- Symbolic regression: fit ln(x) at depth 3 ---\n")
cat("    (paper Sect. 4.3: this should snap to the exact formula)\n")
xs_train <- seq(0.5, 5.0, length.out = 30)
ys_train <- log(xs_train)

# This is slow with SANN; use a moderate iteration count for the demo.
fit <- eml_fit(xs_train, ys_train, depth = 3, maxit = 8000, seed = 1)

cat(sprintf("  continuous MSE: %.3e\n", fit$final_value))
cat(sprintf("  snapped MSE:    %.3e\n", fit$snap_mse))
cat("  (snapped MSE near 0 indicates exact symbolic recovery)\n")
cat("\n")

cat("================================================================\n")
cat(" Done.\n")
cat("================================================================\n")
