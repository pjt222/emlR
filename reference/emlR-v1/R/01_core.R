# =============================================================================
#  emlR: All elementary functions from a single binary operator
#  R implementation of arXiv:2603.21852 (Odrzywolek, 2026)
#
#  The EML (Exp-Minus-Log) operator:
#      eml(x, y) = exp(x) - log(y)
#
#  Together with the constant 1, it generates the full scientific-calculator
#  repertoire. Internal arithmetic is complex (principal branch) because
#  trig functions, pi, and i all require log(-1) = i*pi.
# =============================================================================

#' The EML operator: eml(x, y) = exp(x) - log(y)
#'
#' Evaluates over the complex plane using R's principal-branch log.
#' Inputs are coerced to complex so that log(-1), exp of complex args, etc.
#' all resolve correctly.
#'
#' @param x,y numeric or complex
#' @return complex
#' @export
eml <- function(x, y) {
  exp(as.complex(x)) - log(as.complex(y))
}

#' Real-valued EML, returning the real part.
#'
#' Useful for the final answer when the imaginary residue is numerical noise.
#' Set tol = NA to skip the sanity check.
#' @export
eml_real <- function(x, y, tol = 1e-9) {
  z <- eml(x, y)
  if (!is.na(tol) && abs(Im(z)) > tol) {
    warning(sprintf("eml_real: imaginary part %.3g exceeds tol %.3g",
                    Im(z), tol))
  }
  Re(z)
}

# -----------------------------------------------------------------------------
#  Expression-tree representation
#
#  Grammar (univariate case):   S -> 1 | x | eml(S, S)
#
#  Trees are nested lists with class "eml_tree":
#     leaf:   list(type = "const", value = 1)
#             list(type = "var",   name  = "x")
#     node:   list(type = "eml",   left  = <tree>, right = <tree>)
#
#  We support multiple variables via type = "var".
# -----------------------------------------------------------------------------

# Constructors -----------------------------------------------------------------

#' @export
eml_const <- function(value = 1) {
  structure(list(type = "const", value = value), class = "eml_tree")
}

#' @export
eml_var <- function(name = "x") {
  structure(list(type = "var", name = name), class = "eml_tree")
}

#' Build an EML node. Accepts trees, numerics (auto-wrapped as constants),
#' or character strings (auto-wrapped as variables).
#' @export
eml_node <- function(left, right) {
  structure(
    list(type = "eml", left = as_eml_tree(left), right = as_eml_tree(right)),
    class = "eml_tree"
  )
}

#' Coerce numbers/strings to leaves.
#' @export
as_eml_tree <- function(x) {
  if (inherits(x, "eml_tree")) return(x)
  if (is.character(x) && length(x) == 1L) return(eml_var(x))
  if (is.numeric(x) || is.complex(x)) return(eml_const(x))
  stop("Cannot coerce object of class ", paste(class(x), collapse = "/"),
       " to eml_tree")
}

#' The constant leaf 1 -- the only terminal in the variable-free grammar.
#' @export
ONE <- eml_const(1)
