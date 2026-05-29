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
#' is_eml_expr(quote(x + y)) # FALSE
#' @family eml_predicates
#' @export
is_eml_expr <- function(x) {
  if (is_eml_const(x)) {
    return(TRUE)
  }
  if (is_eml_var(x)) {
    return(TRUE)
  }
  if (is_eml_call(x)) {
    return(is_eml_expr(x[[2L]]) && is_eml_expr(x[[3L]]))
  }
  # Unary +/- on a numeric/complex literal: R's parser turns the source
  # literal `-1` into call("-", 1), so an `eml(...)` argument written as
  # `-1` arrives as a call, not a bare numeric. Accept it only when the
  # operand is a literal -- the documented case -- because such a node
  # denotes the constant -1. Unary +/- on a name or sub-call (`-x`,
  # `-eml(...)`) is not part of the EML grammar, so it is rejected here;
  # this keeps is_eml_expr in agreement with the inspectors (eml_K,
  # eml_depth, eml_rpn) and the compiler, which fold the signed literal
  # back to its constant via .fold_signed_literal().
  if (.is_signed_literal(x)) {
    return(TRUE)
  }
  FALSE
}

# A unary +/- applied to a single numeric/complex literal -- the parse of
# a source token like `-1` as call("-", 1). Denotes a constant and is
# treated as one throughout (predicate, inspectors, compiler).
.is_signed_literal <- function(x) {
  is.call(x) && length(x) == 2L && is.name(x[[1L]]) &&
    as.character(x[[1L]]) %in% c("-", "+") &&
    is_eml_const(x[[2L]])
}

# Fold a signed literal to its numeric/complex value; pass anything else
# through unchanged. Lets the inspectors and compiler treat `-1` exactly
# as the constant -1 instead of crashing on the parser's call("-", 1).
.fold_signed_literal <- function(x) {
  if (.is_signed_literal(x)) eval(x) else x
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
#' is_eml_call(quote(eml(1, x + y))) # TRUE structurally; children not checked
#' is_eml_call(quote(x + y)) # FALSE
#' @family eml_predicates
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
#' is_eml_const(1) # TRUE
#' is_eml_const(0 + 1i) # TRUE
#' is_eml_const(c(1, 2)) # FALSE — length-2 vector
#' is_eml_const(quote(x)) # FALSE — name
#' @family eml_predicates
#' @export
is_eml_const <- function(x) {
  (is.numeric(x) || is.complex(x)) && length(x) == 1L
}

#' Is the object an EML variable reference (a `name`)?
#' @param x object to test.
#' @return Logical scalar.
#' @examples
#' is_eml_var(quote(x)) # TRUE
#' is_eml_var(1) # FALSE — numeric
#' is_eml_var(quote(eml(1, x))) # FALSE — call
#' @family eml_predicates
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
.SAFE_SIMPLIFIER_HEADS <- c(
  "eml", "exp", "log", "sqrt", "sin", "cos",
  "+", "-", "*", "/", "^", "("
)

.tree_uses_only_safe_heads <- function(x) {
  if (is.atomic(x) && length(x) == 1L) {
    return(TRUE)
  }
  if (is.name(x)) {
    return(TRUE)
  }
  if (is.call(x)) {
    head_name <- tryCatch(as.character(x[[1L]]),
      error = function(e) ""
    )
    if (length(head_name) != 1L ||
      !head_name %in% .SAFE_SIMPLIFIER_HEADS) {
      return(FALSE)
    }
    for (i in seq_len(length(x) - 1L) + 1L) {
      if (!.tree_uses_only_safe_heads(x[[i]])) {
        return(FALSE)
      }
    }
    return(TRUE)
  }
  FALSE
}
