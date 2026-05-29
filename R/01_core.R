# =============================================================================
#  Core operator. Identical semantics to v1: complex-domain, principal-branch.
#  Everything else in the package inherits the convention through this entry
#  point.
# =============================================================================

#' The EML operator: `eml(x, y) = exp(x) - log(y)`
#'
#' Evaluates over the complex plane using R's principal-branch `log`.
#' Inputs are coerced to complex so that `log(-1)`, `exp` of a complex
#' argument, and the extended-real values used by some catalog
#' constructions (`log(0) = -Inf`, `exp(-Inf) = 0`) all resolve correctly.
#'
#' @param x,y numeric or complex (length 1 or vectors of equal length).
#' @return Complex.
#' @examples
#' eml(1, 1) # exp(1) - log(1) = e
#' eml(0, -1) # 1 - i*pi    (principal-branch log)
#' Re(eml(-Inf, exp(1))) # -1, via extended-real semantics
#' @seealso [eml_real()] for the real-valued wrapper, [eml_eval()] for
#'   evaluating an EML expression with variable bindings.
#' @export
eml <- function(x, y) {
  exp(as.complex(x)) - log(as.complex(y))
}

#' Real-valued EML, with imaginary-residue check
#'
#' Convenience wrapper: returns `Re(eml(x, y))`, warning if the imaginary
#' residue exceeds `tol` (the real part is still returned). Set
#' `tol = NA` to skip the check.
#'
#' @param x,y numeric or complex.
#' @param tol numeric tolerance for the imaginary residue, or `NA` to
#'   skip the check.
#' @return Numeric.
#' @examples
#' eml_real(1, 1) # e ~ 2.718
#' eml_real(0.5, 1) # exp(0.5)
#' @seealso [eml()] for the underlying complex-domain operator.
#' @export
eml_real <- function(x, y, tol = 1e-9) {
  z <- eml(x, y)
  if (!is.na(tol) && any(abs(Im(z)) > tol, na.rm = TRUE)) {
    warning(sprintf(
      "eml_real: max |Im| = %.3g exceeds tol %.3g",
      max(abs(Im(z)), na.rm = TRUE), tol
    ))
  }
  Re(z)
}
