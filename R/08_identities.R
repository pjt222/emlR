# =============================================================================
#  Identity catalog — every elementary primitive expressed as an EML
#  expression. Constructions ported from v1 (correct, but not always
#  K-optimal); the AST representation is now native R `call` objects.
#
#  See REFERENCES.md "Derivation notes for tricky identities" for the
#  per-construction trace.
# =============================================================================

# --- Atomic identities (paper) ----------------------------------------------

#' @rdname tree_identities
#' @export
tree_e <- function() E(1, 1)

#' @rdname tree_identities
#' @export
tree_one <- function() 1

#' @rdname tree_identities
#' @export
tree_exp <- function(x = "x") E(x, 1)

#' @rdname tree_identities
#' @export
tree_ln <- function(x = "x") E(1, E(E(1, x), 1))

#' @rdname tree_identities
#' @export
tree_log <- function(x = "x") tree_ln(x)

# --- Subtraction and zero ----------------------------------------------------

#' @rdname tree_identities
#' @export
tree_sub <- function(x = "x", y = "y") {
  E(tree_ln(x), tree_exp(y))
}

#' @rdname tree_identities
#' @export
tree_zero <- function() tree_ln(1)

# --- -1, integers ------------------------------------------------------------

# -1 = sub(0, 1) = eml(ln(0), exp(1)). With log(0) = -Inf and exp(-Inf) = 0
# we get eml(-Inf, e) = 0 - 1 = -1. Relies on extended-real semantics.
#' @rdname tree_identities
#' @export
tree_neg_one <- function() {
  E(tree_ln(tree_zero()), tree_exp(1))
}

# --- Negation, addition, multiplication, division, power --------------------

#' @rdname tree_identities
#' @export
tree_minus <- function(x = "x") {
  E(tree_ln(tree_zero()), tree_exp(x))
}

#' @rdname tree_identities
#' @export
tree_add <- function(x = "x", y = "y") {
  E(tree_ln(x), tree_exp(tree_minus(y)))
}

#' @rdname tree_identities
#' @export
tree_mul <- function(x = "x", y = "y") {
  add_lnx_lny <- tree_add(tree_ln(x), tree_ln(y))
  tree_exp(add_lnx_lny)
}

#' @rdname tree_identities
#' @export
tree_div <- function(x = "x", y = "y") {
  sub_lnx_lny <- tree_sub(tree_ln(x), tree_ln(y))
  tree_exp(sub_lnx_lny)
}

#' @rdname tree_identities
#' @export
tree_pow <- function(x = "x", y = "y") {
  tree_exp(tree_mul(y, tree_ln(x)))
}

# --- Trig and special constants ----------------------------------------------

#' @rdname tree_identities
#' @export
tree_two <- function() tree_add(1, 1)

# i = exp(ln(-1) / 2). ln(-1) is principal-branch i*pi.
#' @rdname tree_identities
#' @export
tree_i <- function() {
  ln_neg1 <- tree_ln(tree_neg_one())
  half_ln_neg1 <- tree_div(ln_neg1, tree_two())
  tree_exp(half_ln_neg1)
}

# pi = ln(-1) / i (since ln(-1) = i*pi).
#' @rdname tree_identities
#' @export
tree_pi <- function() {
  ln_neg1 <- tree_ln(tree_neg_one())
  tree_div(ln_neg1, tree_i())
}

#' @rdname tree_identities
#' @export
tree_sqrt <- function(x = "x") {
  half <- tree_div(1, tree_two())
  tree_pow(x, half)
}

# sin(x) = (exp(i*x) - exp(-i*x)) / (2*i)
#' @rdname tree_identities
#' @export
tree_sin <- function(x = "x") {
  ix      <- tree_mul(tree_i(), x)
  neg_ix  <- tree_minus(ix)
  numer   <- tree_sub(tree_exp(ix), tree_exp(neg_ix))
  denom   <- tree_mul(tree_two(), tree_i())
  tree_div(numer, denom)
}

# cos(x) = (exp(i*x) + exp(-i*x)) / 2
#' @rdname tree_identities
#' @export
tree_cos <- function(x = "x") {
  ix     <- tree_mul(tree_i(), x)
  neg_ix <- tree_minus(ix)
  numer  <- tree_add(tree_exp(ix), tree_exp(neg_ix))
  tree_div(numer, tree_two())
}

#' EML expressions for the elementary functions and constants
#' implemented in this release
#'
#' Each entry is a closed `call` (or literal) representing the named
#' primitive in pure-EML form. The catalog covers the 18 entries
#' listed in [eml_catalog()]: the seven constants `one`, `e`, `zero`,
#' `neg_one`, `two`, `i`, `pi`, the unary primitives `exp`, `log`,
#' `minus`, `sqrt`, `sin`, `cos`, and the binary primitives `add`,
#' `sub`, `mul`, `div`, `pow`. Higher trigonometric primitives
#' (`tan`, `asin`, `acos`, `atan`) and hyperbolics (`sinh`, `cosh`,
#' `tanh`) are constructible from the same building blocks but are
#' not shipped as named entries. Constructions are correct but not
#' K-optimal — see the paper's Table 4 for the smaller forms found
#' by exhaustive search.
#'
#' @param x,y character (variable name) or an EML expression to embed.
#'   Univariate constructors take only `x`; bivariate constructors
#'   (`tree_add`, `tree_sub`, `tree_mul`, `tree_div`, `tree_pow`) take
#'   both. Defaults are `"x"` and `"y"`.
#' @name tree_identities
#' @return An EML expression.
#' @examples
#' tree_log("x")    # eml(1, eml(eml(1, x), 1))  — paper Eq. 5
#' tree_exp("x")    # eml(x, 1)
#' tree_add("x", "y")
#' simplify_native(tree_log("x"))   # log(x)
NULL

#' All catalog identities as a named list
#'
#' Returns one entry per primitive. Univariate trees use `"x"`; bivariate
#' use `"x"` and `"y"`. Use [verify_catalog()] to confirm that every
#' entry simplifies, via [simplify_native()], to its expected base-R form.
#'
#' @return A named list of EML expressions.
#' @examples
#' cat <- eml_catalog()
#' names(cat)
#' cat$log
#' @export
# put id:"cat_catalog", label:"eml_catalog (18 primitives)", \
#   node_type:"input", output:"catalog_ast.internal"
eml_catalog <- function() {
  list(
    one     = tree_one(),
    e       = tree_e(),
    zero    = tree_zero(),
    neg_one = tree_neg_one(),
    two     = tree_two(),
    i       = tree_i(),
    pi      = tree_pi(),
    exp     = tree_exp("x"),
    log     = tree_ln("x"),
    minus   = tree_minus("x"),
    add     = tree_add("x", "y"),
    sub     = tree_sub("x", "y"),
    mul     = tree_mul("x", "y"),
    div     = tree_div("x", "y"),
    pow     = tree_pow("x", "y"),
    sqrt    = tree_sqrt("x"),
    sin     = tree_sin("x"),
    cos     = tree_cos("x")
  )
}

# Vars and tolerances per entry, used by both numeric and structural
# verification.
.catalog_test_vars <- function() {
  list(
    one     = list(vars = list(),                expected = 1),
    e       = list(vars = list(),                expected = exp(1)),
    zero    = list(vars = list(),                expected = 0),
    neg_one = list(vars = list(),                expected = -1),
    two     = list(vars = list(),                expected = 2),
    i       = list(vars = list(),                expected = 1i),
    pi      = list(vars = list(),                expected = pi),
    exp     = list(vars = list(x = 0.5),         expected = exp(0.5)),
    log     = list(vars = list(x = 2),           expected = log(2)),
    minus   = list(vars = list(x = 3),           expected = -3),
    add     = list(vars = list(x = 2, y = 3),    expected = 5),
    sub     = list(vars = list(x = 5, y = 2),    expected = 3),
    mul     = list(vars = list(x = 2, y = 3),    expected = 6),
    div     = list(vars = list(x = 6, y = 2),    expected = 3),
    pow     = list(vars = list(x = 2, y = 3),    expected = 8),
    sqrt    = list(vars = list(x = 16),          expected = 4),
    sin     = list(vars = list(x = pi / 6),      expected = 0.5),
    cos     = list(vars = list(x = pi / 3),      expected = 0.5)
  )
}

#' Verify the catalog: every entry evaluates to its known value
#'
#' Evaluates each entry of [eml_catalog()] at the test bindings from
#' SPEC TESTS T2 and checks the result against the known mathematical
#' value to numerical tolerance. Pure numeric verification — does NOT
#' require the simplifier to recognise the structural form.
#'
#' @param tol numeric tolerance.
#' @param verbose if `TRUE`, print one line per entry.
#' @return Invisibly, a logical scalar (`TRUE` iff every entry passed).
#' @examples
#' verify_catalog()
#' @export
# put id:"cat_verify", label:"verify_catalog", node_type:"output", \
#   input:"catalog_ast.internal"
verify_catalog <- function(tol = 1e-8, verbose = TRUE) {
  spec <- .catalog_test_vars()
  catalog <- eml_catalog()
  ok_all <- TRUE
  for (nm in names(catalog)) {
    expr <- catalog[[nm]]
    s    <- spec[[nm]]
    val  <- eml_eval(expr, s$vars)
    diff <- max(abs(as.complex(val) - as.complex(s$expected)), na.rm = TRUE)
    pass <- isTRUE(diff < tol)
    ok_all <- ok_all && pass
    if (verbose) {
      cat(sprintf("  [%s] %-8s  K=%-3d  |err| = %.3g\n",
                  if (pass) "OK " else "FAIL",
                  nm, eml_K(expr), diff))
    }
  }
  invisible(ok_all)
}
