# =============================================================================
#  Inspection: K (paper node count), depth, RPN serialisation, leaf count.
#
#  ADR-001: K counts every node (leaves + interior), matching the paper's
#  Table 4 / RPN-length definition. v1 returned only the leaf count;
#  that v1 behaviour is preserved as `eml_leafcount()`.
# =============================================================================

#' Total node count K of an EML expression (paper definition)
#'
#' Counts every node in the tree — both leaves (literals and variables)
#' and interior `eml` nodes. This matches Odrzywolek (2026), Table 4 and
#' Eq. 5: for `log(x) = eml(1, eml(eml(1, x), 1))`, `eml_K` returns 7.
#'
#' This is a behaviour change from v1, which returned the leaf count
#' (4 for the same expression). v1 semantics are still available via
#' [eml_leafcount()]. See `ADR-001-K-counting.md` in the spec bundle.
#'
#' @param expr an EML expression.
#' @return Integer scalar.
#' @examples
#' eml_K(quote(eml(1, 1)))                              # 3 (e)
#' eml_K(quote(eml(x, 1)))                              # 3 (exp)
#' eml_K(quote(eml(1, eml(eml(1, x), 1))))              # 7 (log, paper Eq. 5)
#' @export
eml_K <- function(expr) {
  if (is_eml_const(expr) || is_eml_var(expr)) return(1L)
  if (is_eml_call(expr)) {
    return(1L + eml_K(expr[[2L]]) + eml_K(expr[[3L]]))
  }
  stop("eml_K: not an EML expression (",
       paste(class(expr), collapse = "/"), ").")
}

#' Alias for [eml_K()] — returns total node count.
#' @inheritParams eml_K
#' @export
eml_nodecount <- function(expr) eml_K(expr)

#' Leaf count of an EML expression (v1 semantics)
#'
#' Counts only the leaves — literals and variables — exactly as v1's
#' `eml_K()` did. Provided for backwards compatibility; the paper's K
#' is total node count, so prefer [eml_K()] in new code.
#'
#' @param expr an EML expression.
#' @return Integer scalar.
#' @examples
#' eml_leafcount(quote(eml(1, eml(eml(1, x), 1))))      # 4 (v1 behaviour)
#' @export
eml_leafcount <- function(expr) {
  if (is_eml_const(expr) || is_eml_var(expr)) return(1L)
  if (is_eml_call(expr)) {
    return(eml_leafcount(expr[[2L]]) + eml_leafcount(expr[[3L]]))
  }
  stop("eml_leafcount: not an EML expression (",
       paste(class(expr), collapse = "/"), ").")
}

#' Depth of an EML expression
#'
#' Leaves have depth 0; an `eml` node has depth `1 + max(depth(left),
#' depth(right))`.
#'
#' @param expr an EML expression.
#' @return Integer scalar.
#' @examples
#' eml_depth(quote(eml(x, 1)))                          # 1
#' eml_depth(quote(eml(1, eml(eml(1, x), 1))))          # 3
#' @export
eml_depth <- function(expr) {
  if (is_eml_const(expr) || is_eml_var(expr)) return(0L)
  if (is_eml_call(expr)) {
    return(1L + max(eml_depth(expr[[2L]]), eml_depth(expr[[3L]])))
  }
  stop("eml_depth: not an EML expression (",
       paste(class(expr), collapse = "/"), ").")
}

#' Reverse Polish Notation (RPN) serialisation
#'
#' Returns a single space-separated string. Constants are formatted via
#' `format()`; variables print as their name; each `eml` node emits an
#' `E` after its operands. Matches the paper's RPN convention: for
#' `log(x)`, returns `"1 1 x E 1 E E"` (7 tokens, K=7).
#'
#' @param expr an EML expression.
#' @return Character scalar.
#' @examples
#' eml_rpn(quote(eml(x, 1)))                            # "x 1 E"
#' eml_rpn(quote(eml(1, eml(eml(1, x), 1))))            # "1 1 x E 1 E E"
#' @export
eml_rpn <- function(expr) {
  if (is_eml_const(expr)) return(format(expr))
  if (is_eml_var(expr))   return(as.character(expr))
  if (is_eml_call(expr)) {
    return(paste(eml_rpn(expr[[2L]]), eml_rpn(expr[[3L]]), "E"))
  }
  stop("eml_rpn: not an EML expression (",
       paste(class(expr), collapse = "/"), ").")
}
