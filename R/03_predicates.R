# =============================================================================
#  Type predicates for EML expressions.
# =============================================================================

#' Is the object an EML expression?
#'
#' TRUE for length-1 numeric/complex, names, and `eml` calls (including
#' nested ones). Returns FALSE for arbitrary calls — `quote(x + y)` is
#' not an EML expression.
#'
#' @param x object to test.
#' @return Logical scalar.
#' @examples
#' is_eml_expr(1)
#' is_eml_expr(quote(x))
#' is_eml_expr(quote(eml(1, x)))
#' is_eml_expr(quote(x + y))     # FALSE
#' @export
is_eml_expr <- function(x) {
  if (is_eml_const(x)) return(TRUE)
  if (is_eml_var(x))   return(TRUE)
  if (is_eml_call(x)) {
    return(is_eml_expr(x[[2L]]) && is_eml_expr(x[[3L]]))
  }
  FALSE
}

#' Is the object an `eml(l, r)` call?
#'
#' Strict syntactic check: `is.call(x)` and the head is the symbol `eml`
#' and the call has exactly two arguments. Does not recurse into the
#' children.
#'
#' @param x object to test.
#' @return Logical scalar.
#' @examples
#' is_eml_call(quote(eml(1, x)))
#' is_eml_call(quote(eml(1, x + y)))   # TRUE structurally; children not checked
#' is_eml_call(quote(x + y))            # FALSE
#' @export
is_eml_call <- function(x) {
  is.call(x) &&
    length(x) == 3L &&
    identical(x[[1L]], as.name("eml"))
}

#' Is the object an EML constant literal?
#' @param x object to test.
#' @return Logical scalar.
#' @export
is_eml_const <- function(x) {
  (is.numeric(x) || is.complex(x)) && length(x) == 1L
}

#' Is the object an EML variable reference (a `name`)?
#' @param x object to test.
#' @return Logical scalar.
#' @export
is_eml_var <- function(x) {
  is.name(x)
}
