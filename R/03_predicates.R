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
  # Unary +/- wrappers: R's parser turns the source literal `-1`
  # into call("-", 1), so an `eml(...)` argument written as `-1`
  # arrives as a call, not a bare numeric. Treat unary +/- on an
  # EML expression as an EML expression.
  if (is.call(x) && length(x) == 2L &&
      is.name(x[[1L]]) &&
      as.character(x[[1L]]) %in% c("-", "+")) {
    return(is_eml_expr(x[[2L]]))
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
#' @examples
#' is_eml_const(1)               # TRUE
#' is_eml_const(0+1i)             # TRUE
#' is_eml_const(c(1, 2))          # FALSE — length-2 vector
#' is_eml_const(quote(x))         # FALSE — name
#' @export
is_eml_const <- function(x) {
  (is.numeric(x) || is.complex(x)) && length(x) == 1L
}

#' Is the object an EML variable reference (a `name`)?
#' @param x object to test.
#' @return Logical scalar.
#' @examples
#' is_eml_var(quote(x))           # TRUE
#' is_eml_var(1)                  # FALSE — numeric
#' is_eml_var(quote(eml(1, x)))   # FALSE — call
#' @export
is_eml_var <- function(x) {
  is.name(x)
}

# Safe-heads predicate used by the simplifier entry guards. Permits
# re-application of simplifier output (which contains exp/log/sqrt
# and arithmetic operators) but rejects arbitrary R calls — most
# importantly, side-effecting ones such as `system`, `source`, or
# `do.call`. This is the primary defence against SPEC-§2.1
# adversarial input flowing into `.fold_constants` or `eval()`.
.SAFE_SIMPLIFIER_HEADS <- c("eml", "exp", "log", "sqrt", "sin", "cos",
                            "+", "-", "*", "/", "^", "(")

.tree_uses_only_safe_heads <- function(x) {
  if (is.atomic(x) && length(x) == 1L) return(TRUE)
  if (is.name(x)) return(TRUE)
  if (is.call(x)) {
    head_name <- tryCatch(as.character(x[[1L]]),
                          error = function(e) "")
    if (length(head_name) != 1L ||
        !head_name %in% .SAFE_SIMPLIFIER_HEADS) {
      return(FALSE)
    }
    for (i in seq_len(length(x) - 1L) + 1L) {
      if (!.tree_uses_only_safe_heads(x[[i]])) return(FALSE)
    }
    return(TRUE)
  }
  FALSE
}
