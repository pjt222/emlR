#' emlR: All Elementary Functions From a Single Binary Operator
#'
#' R implementation of the EML (Exp-Minus-Log) Sheffer operator
#' `eml(x, y) = exp(x) - log(y)` from Odrzywolek (2026), arXiv:2603.21852.
#' Together with the constant `1`, EML generates the full
#' scientific-calculator repertoire over the complex numbers (principal
#' branch).
#'
#' @section Architecture:
#' EML expressions are native R `call` objects, not a custom S3 class.
#' This buys free interop with [base::deparse], [base::bquote],
#' [base::all.vars], [base::eval], and [Deriv::Deriv].
#'
#' Key entry points:
#' \itemize{
#'   \item [eml()] — the operator itself
#'   \item [eml_eval()] — evaluate an expression at variable bindings
#'   \item [compile_eml()] / [run_bytecode()] — vectorised fast path
#'   \item [simplify_eml()] / [simplify_native()] — rewriters
#'   \item [eml_catalog()] — every primitive elementary function as EML
#'   \item [eml_fit()] — symbolic regression via the master formula
#' }
#'
#' @name emlR-package
#' @importFrom Deriv Deriv
#' @importFrom stats optim rnorm
"_PACKAGE"
