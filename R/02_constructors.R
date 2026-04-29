# =============================================================================
#  Constructors for native-AST EML expressions.
#
#  An EML expression is one of:
#    - a length-1 numeric or complex literal
#    - a `name` (i.e. R symbol)
#    - a `call` of the form `eml(left, right)`
#  No custom S3 class. `class(expr)` is whatever R says.
# =============================================================================

# put id:"con_build", label:"Construct EML AST", node_type:"input", \
#   output:"ast.internal"

#' Construct a literal EML constant
#'
#' Identity on numeric/complex input; the literal is its own EML
#' expression. Provided for symmetry with [eml_var()] and [eml_node()].
#'
#' @param value length-1 numeric or complex.
#' @return The same value (no wrapping).
#' @examples
#' eml_const(1)
#' eml_const(0 + 1i)
#' @family eml_constructors
#' @export
eml_const <- function(value = 1) {
  if (!(is.numeric(value) || is.complex(value)) || length(value) != 1L) {
    stop("eml_const: value must be a length-1 numeric or complex.")
  }
  value
}

#' Construct an EML variable reference
#'
#' Returns an R `name` (symbol). Accepts a string or an existing name.
#'
#' @param name a character string or `name`.
#' @return A `name`.
#' @examples
#' eml_var("x")
#' identical(eml_var("x"), eml_var(as.name("x")))
#' @family eml_constructors
#' @export
eml_var <- function(name = "x") {
  if (is.name(name)) {
    return(name)
  }
  if (is.character(name) && length(name) == 1L && nzchar(name)) {
    return(as.name(name))
  }
  stop("eml_var: name must be a non-empty character scalar or a `name`.")
}

#' Construct an EML node
#'
#' Returns a `call` of the form `eml(left, right)`. Children are coerced
#' through [as_eml_expr()], so numerics, complex, names, and existing
#' calls all flow through unchanged or wrapped appropriately.
#'
#' @param left,right child expressions.
#' @return A `call`.
#' @examples
#' eml_node(1, "x") # eml(1, x)
#' eml_node(1, eml_node(eml_node(1, "x"), 1)) # paper Eq. 5
#' @family eml_constructors
#' @export
eml_node <- function(left, right) {
  call("eml", as_eml_expr(left), as_eml_expr(right))
}

#' Coerce an arbitrary input to an EML expression
#'
#' \describe{
#'   \item{numeric / complex (length 1)}{passed through unchanged.}
#'   \item{character (length 1)}{interpreted as a variable name and
#'     converted via [as.name()].}
#'   \item{`name` or `call`}{passed through unchanged.}
#'   \item{anything else}{error.}
#' }
#'
#' Length-1 numerics are NOT wrapped — the literal `2` is itself a
#' valid EML expression.
#'
#' @param x input to coerce.
#' @return An EML expression (literal, name, or call).
#' @examples
#' as_eml_expr(2)
#' as_eml_expr("x")
#' as_eml_expr(quote(eml(1, x)))
#' @family eml_constructors
#' @export
as_eml_expr <- function(x) {
  if (is.call(x)) {
    return(x)
  }
  if (is.name(x)) {
    return(x)
  }
  if ((is.numeric(x) || is.complex(x)) && length(x) == 1L) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L && nzchar(x)) {
    return(as.name(x))
  }
  stop(
    "as_eml_expr: cannot coerce object of class ",
    paste(class(x), collapse = "/"), " (length ", length(x), ")."
  )
}

#' Shorthand for [eml_node()]
#'
#' `E(l, r)` is equivalent to `eml_node(l, r)`. Provided so that the
#' v1-style constructions read identically:
#' `E(1, E(E(1, "x"), 1))` builds the same `call` as
#' `quote(eml(1, eml(eml(1, x), 1)))`.
#'
#' @param left,right child expressions.
#' @return A `call`.
#' @examples
#' E(1, E(E(1, "x"), 1))
#' @family eml_constructors
#' @export
E <- function(left, right) eml_node(left, right)
