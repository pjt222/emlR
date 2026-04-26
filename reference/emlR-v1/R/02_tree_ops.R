# =============================================================================
#  Tree operations: evaluate, serialize, pretty-print, count leaves
# =============================================================================

#' Evaluate an EML tree at given variable bindings.
#'
#' @param tree an `eml_tree`
#' @param vars named list of variable values (e.g. list(x = 2, y = 3)).
#'             Values are coerced to complex.
#' @return complex scalar (or vector if vars are vectors)
#' @export
eml_eval <- function(tree, vars = list()) {
  switch(tree$type,
    const = as.complex(tree$value),
    var   = {
      if (is.null(vars[[tree$name]])) {
        stop("Variable '", tree$name, "' not provided in vars")
      }
      as.complex(vars[[tree$name]])
    },
    eml   = eml(eml_eval(tree$left,  vars),
                eml_eval(tree$right, vars)),
    stop("Unknown node type: ", tree$type)
  )
}

#' Real-part wrapper with imaginary-residue check.
#' @export
eml_eval_real <- function(tree, vars = list(), tol = 1e-8) {
  z <- eml_eval(tree, vars)
  if (!is.na(tol) && any(abs(Im(z)) > tol, na.rm = TRUE)) {
    warning(sprintf("eml_eval_real: max |Im| = %.3g exceeds tol %.3g",
                    max(abs(Im(z)), na.rm = TRUE), tol))
  }
  Re(z)
}

#' Number of leaves in the tree (the `K` from the paper, Table 4).
#' Equals Mathematica's LeafCount on the same expression.
#' @export
eml_K <- function(tree) {
  if (tree$type %in% c("const", "var")) 1L
  else eml_K(tree$left) + eml_K(tree$right)
}

#' Reverse Polish Notation serialization. The paper writes ln as
#'    1, 1, x, eml, 1, eml, eml      (K = 7)
#' which prints as  "1 1 x E 1 E E".
#' @export
eml_rpn <- function(tree) {
  switch(tree$type,
    const = format(tree$value),
    var   = tree$name,
    eml   = paste(eml_rpn(tree$left), eml_rpn(tree$right), "E"),
    stop("Unknown node type")
  )
}

#' Pretty-print as nested eml(...) form.
#' @export
format.eml_tree <- function(x, ...) {
  switch(x$type,
    const = format(x$value),
    var   = x$name,
    eml   = sprintf("eml(%s, %s)",
                    format.eml_tree(x$left),
                    format.eml_tree(x$right))
  )
}

#' @export
print.eml_tree <- function(x, ...) {
  cat(format.eml_tree(x), "\n", sep = "")
  invisible(x)
}

#' Tree depth (root = 0, leaves contribute up).
#' @export
eml_depth <- function(tree) {
  if (tree$type %in% c("const", "var")) 0L
  else 1L + max(eml_depth(tree$left), eml_depth(tree$right))
}
