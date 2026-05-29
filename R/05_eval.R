# =============================================================================
#  Evaluation. Builds an environment containing the `eml` operator and the
#  user-supplied bindings, then defers to `base::eval`. Vectorised input
#  values flow through unchanged because `exp` and `log` are vectorised.
# =============================================================================

#' Evaluate an EML expression at variable bindings
#'
#' Builds an environment containing the `eml` operator and the
#' user-supplied bindings, then defers to [base::eval]. Vectorised
#' inputs are supported transparently — if `vars$x` is length N, the
#' result is length N.
#'
#' By default the result is complex (the principal-branch domain of
#' EML). Set `real = TRUE` to return `Re(z)`, warning if the imaginary
#' residue exceeds `tol` (the real part is still returned).
#'
#' @param expr an EML expression.
#' @param vars named list of variable bindings, e.g. `list(x = 2)`.
#' @param real logical; if `TRUE`, return the real part with an
#'   imaginary-residue check.
#' @param tol numeric tolerance for the residue check, or `NA` to skip.
#' @return Complex (or numeric, if `real = TRUE`).
#' @examples
#' # exp(2)
#' eml_eval(quote(eml(x, 1)), list(x = 2), real = TRUE)
#'
#' # Vectorised: log evaluated at 30 points
#' xs <- seq(0.5, 5, length.out = 30)
#' lx <- eml_eval(quote(eml(1, eml(eml(1, x), 1))),
#'   list(x = xs),
#'   real = TRUE
#' )
#' max(abs(lx - log(xs)))
#' @seealso [compile_eml()] / [run_bytecode()] for the vectorised
#'   stack-machine evaluator with the same semantics.
#' @export
# put id:"ev_eval", label:"eml_eval (one-off)", node_type:"output", \
#   input:"ast.internal"
eml_eval <- function(expr, vars = list(), real = FALSE, tol = 1e-8) {
  if (!is_eml_expr(expr)) {
    stop(
      "eml_eval: `expr` must be an EML expression. ",
      "Use `eval(expr, ...)` directly to evaluate other R calls."
    )
  }
  if (!is.list(vars)) {
    stop("eml_eval: `vars` must be a (possibly empty) named list.")
  }
  if (length(vars) > 0L &&
    (is.null(names(vars)) || !all(nzchar(names(vars))))) {
    stop("eml_eval: every entry of `vars` must be named.")
  }
  # Restrict the eval env: only the EML operator and the user-supplied
  # bindings are visible. parent = emptyenv() blocks resolution of any
  # base-R function (system, source, file, ...) that an adversarial
  # call head could otherwise reach.
  #
  # Unary +/- and parens are injected explicitly because R parses
  # source-level negative literals (`-1`) as `call("-", 1)`, and
  # parenthesised expressions as calls to `(`. The is_eml_expr guard
  # already constrains call heads to the safe set; these injections
  # let the legitimate ones evaluate.
  env <- list2env(c(
    list(
      eml = eml,
      `-` = `-`, `+` = `+`, `(` = `(`
    ),
    vars
  ), parent = emptyenv())
  z <- eval(expr, envir = env)
  # Always return complex from the default path (SPEC §2.2). A bare-leaf
  # expression like `expr = 2` evaluates to numeric otherwise, breaking
  # type-strict equivalence checks against the bytecode evaluator.
  if (!is.complex(z)) z <- as.complex(z)
  if (isTRUE(real)) {
    if (!is.na(tol) && any(abs(Im(z)) > tol, na.rm = TRUE)) {
      warning(sprintf(
        "eml_eval: max |Im| = %.3g exceeds tol %.3g",
        max(abs(Im(z)), na.rm = TRUE), tol
      ))
    }
    return(Re(z))
  }
  z
}
