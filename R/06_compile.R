# =============================================================================
#  Bytecode compiler and stack-machine evaluator.
#
#  Three-opcode ISA per SPEC §4. Post-order walk emits LIT(idx) for every
#  literal, VAR(idx) for every name, and EML for every interior node.
#  The constants pool is deduplicated; the stack is preallocated to the
#  exact maximum depth required.
# =============================================================================

# Opcode constants (kept internal — SPEC defines the numbers).
.OP_LIT <- 0L
.OP_VAR <- 1L
.OP_EML <- 2L

#' Compile an EML expression to bytecode
#'
#' Produces a flat instruction stream suitable for [run_bytecode()].
#' Compilation is a post-order tree walk; each leaf emits a LIT or VAR,
#' each interior node emits an EML. The constants pool deduplicates
#' identical literals (`eml(1, eml(1, x))` has one shared entry for `1`).
#'
#' @param expr an EML expression.
#' @return A list with elements:
#' \describe{
#'   \item{`ops`}{integer vector of opcodes (0 LIT, 1 VAR, 2 EML).}
#'   \item{`args`}{integer vector of opcode arguments (constant index for
#'     LIT, variable index for VAR, 0 for EML).}
#'   \item{`consts`}{complex vector — the deduplicated constants pool.}
#'   \item{`vars`}{character vector — variable names in declaration order.}
#'   \item{`max_stack`}{integer — the peak stack depth required.}
#'   \item{`source`}{the original `expr`, for inspection.}
#' }
#' @examples
#' bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
#' bc$ops              # 0 0 1 2 0 2 2
#' bc$consts           # 1+0i
#' bc$vars             # "x"
#' @seealso [run_bytecode()] for executing the compiled output;
#'   [eml_eval()] for the slower tree-walking evaluator.
#' @export
# put id:"bc_compile", label:"compile_eml", node_type:"process", \
#   input:"ast.internal", output:"bytecode.internal"
compile_eml <- function(expr) {
  if (!is_eml_expr(expr)) {
    stop("compile_eml: not an EML expression (",
         paste(class(expr), collapse = "/"), ").")
  }

  # Pre-size the buffers using the K (total node count); each node emits
  # exactly one opcode.
  K <- eml_K(expr)
  ops  <- integer(K)
  args <- integer(K)
  pos  <- 0L

  consts <- complex(0)
  vars_n <- character(0)

  add_const <- function(v) {
    v <- as.complex(v)
    if (length(consts) > 0L) {
      hit <- which(consts == v &
                   abs(Re(consts) - Re(v)) == 0 &
                   abs(Im(consts) - Im(v)) == 0)
      if (length(hit) > 0L) return(hit[1L])
    }
    consts[[length(consts) + 1L]] <<- v
    length(consts)
  }

  add_var <- function(nm) {
    if (length(vars_n) > 0L) {
      hit <- which(vars_n == nm)
      if (length(hit) > 0L) return(hit[1L])
    }
    vars_n[[length(vars_n) + 1L]] <<- nm
    length(vars_n)
  }

  emit <- function(op, a) {
    pos <<- pos + 1L
    ops[pos]  <<- op
    args[pos] <<- a
  }

  walk <- function(e) {
    if (is_eml_const(e)) {
      emit(.OP_LIT, add_const(e))
    } else if (is_eml_var(e)) {
      emit(.OP_VAR, add_var(as.character(e)))
    } else if (is_eml_call(e)) {
      walk(e[[2L]])
      walk(e[[3L]])
      emit(.OP_EML, 0L)
    } else {
      stop("compile_eml: encountered non-EML subexpression: ", deparse(e))
    }
  }

  walk(expr)

  max_stack <- .max_stack_depth(ops)

  list(
    ops       = ops,
    args      = args,
    consts    = consts,
    vars      = vars_n,
    max_stack = max_stack,
    source    = expr
  )
}

# Walk the opcode stream, returning the peak stack depth. LIT/VAR push
# (+1); EML pops two, pushes one (net -1). Used at compile time to size
# the stack; at run time the assertion is internal.
.max_stack_depth <- function(ops) {
  sp <- 0L
  mx <- 0L
  for (op in ops) {
    if (op == .OP_LIT || op == .OP_VAR) {
      sp <- sp + 1L
      if (sp > mx) mx <- sp
    } else {
      # EML: -2 push +1 = net -1
      sp <- sp - 1L
    }
  }
  mx
}

#' Run compiled EML bytecode at variable bindings
#'
#' Stack-machine evaluator. The stack is a preallocated list of complex
#' vectors; each VAR slot can carry a length-N input, in which case
#' every interior node is computed elementwise via vectorised
#' [base::exp] and [base::log]. Returns a complex vector matching the
#' input length.
#'
#' Same semantics as [eml_eval()], including principal-branch and
#' extended-real conventions.
#'
#' @param bc compiled bytecode object from [compile_eml()].
#' @param vars named list of variable bindings.
#' @return Complex vector.
#' @examples
#' bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
#' xs <- seq(0.5, 5, length.out = 30)
#' Re(run_bytecode(bc, list(x = xs)))     # log(xs)
#' @seealso [compile_eml()] for producing the bytecode object;
#'   [eml_eval()] for the slower tree-walking evaluator.
#' @export
# put id:"bc_run", label:"run_bytecode (vectorised)", node_type:"output", \
#   input:"bytecode.internal"
run_bytecode <- function(bc, vars = list()) {
  if (!is.list(vars)) {
    stop("run_bytecode: `vars` must be a (possibly empty) named list.")
  }
  # Resolve variable values once; coerce to complex.
  if (length(bc$vars) > 0L) {
    missing <- setdiff(bc$vars, names(vars))
    if (length(missing) > 0L) {
      stop("run_bytecode: missing variable bindings: ",
           paste(missing, collapse = ", "))
    }
    var_vals <- lapply(bc$vars, function(nm) as.complex(vars[[nm]]))
  } else {
    var_vals <- list()
  }

  stack <- vector("list", bc$max_stack)
  sp <- 0L
  ops  <- bc$ops
  args <- bc$args
  consts <- bc$consts

  for (k in seq_along(ops)) {
    op <- ops[k]
    a  <- args[k]
    if (op == .OP_LIT) {
      sp <- sp + 1L
      stack[[sp]] <- consts[a]
    } else if (op == .OP_VAR) {
      sp <- sp + 1L
      stack[[sp]] <- var_vals[[a]]
    } else {  # EML
      sp <- sp - 1L
      stack[[sp]] <- exp(stack[[sp]]) - log(stack[[sp + 1L]])
    }
  }

  stack[[1L]]
}
