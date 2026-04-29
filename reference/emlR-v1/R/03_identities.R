# =============================================================================
#  Identity library
#
#  This file builds elementary functions and constants out of EML and 1,
#  following the bootstrapping chain in Odrzywolek (2026), Fig. 1.
#
#  Two identities are stated explicitly in the paper:
#
#     e         = eml(1, 1)                                        Eq. after (4)
#     exp(x)    = eml(x, 1)                                        Sec. 1
#     ln(x)     = eml(1, eml(eml(1, x), 1))                        Eq. (5), K = 7
#
#  Everything else is derived constructively. These are NOT claimed to be
#  the K-optimal trees from Table 4 of the paper -- those came from
#  exhaustive search up to K = 9 and are not all printed in the article.
#  These are correct identities, sufficient for evaluation and demos.
#
#  Sketch of the derivations:
#
#     exp(x) = eml(x, 1)                          (paper)
#     ln(y)  = eml(1, eml(eml(1, y), 1))          (paper, Eq. 5)
#     e      = eml(1, 1)                          (paper)
#     x - y  = eml(ln(x), exp(y))                 since exp(ln x) - ln(exp y) = x - y
#     x + y  = ln( exp(x) * exp(y) )    -- but we don't have *, so:
#            = -(-x - y) and we build minus via exp/log identities, see below
#
#  We use the cleaner exp/log bootstrap:
#     mul(x, y) = exp(ln(x) + ln(y)),   add(x, y) = ln(exp(x) * exp(y))
#  but inside EML we have to express + and * recursively, so we choose:
#     sub(x, y) = eml(ln(x), exp(y))   <-- one node, very clean
#     neg(x)   = sub(0, x),  with 0 built from a constant tree
#
#  See the paper's bootstrap chain (Fig. 1) for the canonical order; this is
#  one valid order out of many.
# =============================================================================

# ------------------------- Atomic identities ---------------------------------

#' Tree for the constant e.  e = eml(1, 1).
#' @export
tree_e <- function() Eml(1, 1)

#' Tree for exp(x).  exp(x) = eml(x, 1).
#' @export
tree_exp <- function(x = "x") Eml(x, 1)

#' Tree for ln(x).  ln(x) = eml(1, eml(eml(1, x), 1)).  Paper Eq. (5), K = 7.
#' @export
tree_ln <- function(x = "x") Eml(1, Eml(Eml(1, x), 1))

# ------------------------- Subtraction ---------------------------------------
# x - y = eml(ln(x), exp(y))
#       = exp(ln(x)) - ln(exp(y))
#       = x - y      (for x > 0; in general handled via principal branch)

#' Tree for x - y.
#' @export
tree_sub <- function(x = "x", y = "y") {
  Eml(tree_ln(x), tree_exp(y))
}

# ------------------------- Zero, -1, integers -------------------------------
# 0 = x - x.  The paper notes Calc 2 generates 0 this way.
# But we want 0 as a *closed* tree (no free variable).  Use 0 = e - e.
# In EML form: 0 = eml(ln(e), exp(e)) = eml(1, exp(e)).
# And exp(e) = eml(e, 1) = eml(eml(1,1), 1). Substitute:
#     0 = eml(1, eml(eml(1,1), 1))
# (which incidentally is also what you get from eml(1, exp(e)) -- same shape
# as ln applied to e.  And indeed ln(e) = 1, so eml(1, exp(e)) makes sense
# only if we want a *zero* node.  Let's verify by evaluation.

#' Tree for the constant 0.  Construction: 0 = ln(e) - ln(e) ... easier:
#' use the identity 0 = e - e written in EML.
#' We have e = eml(1,1).  So:
#'    0 = sub(e, e) = eml(ln(e), exp(e)) = eml(eml(1, eml(eml(1, eml(1,1)), 1)),
#'                                              eml(eml(1,1), 1))
#' That works but is large.  A simpler closed form: ln(1) = 0 directly.
#'    0 = ln(1) = eml(1, eml(eml(1, 1), 1))
#' which is just `tree_ln` evaluated at the *constant* 1. K = 7.
#' @export
tree_zero <- function() tree_ln(1)

#' Tree for -1.  Use -1 = 0 - 1 = sub(0, 1) at the leaf level.
#' But sub takes trees; we feed it constants.
#' @export
tree_neg_one <- function() Eml(tree_ln(tree_zero()),  # ln(0) = -Inf in extended reals
                              tree_exp(1))           # exp(1) = e
# Actually that gives -Inf - e, not -1.  Let me redo.
# We want -1.  -1 = sub(0, 1) literally: eml(ln(0), exp(1)).
# But ln(0) = -Inf, so eml(-Inf, e) = exp(-Inf) - ln(e) = 0 - 1 = -1.  
# This relies on extended reals: exp(-Inf) = 0. The paper covers this in 4.1.
# So tree_neg_one above IS correct as written.

#' Tree for the constant 1 (trivial -- just the leaf).
#' @export
tree_one <- function() eml_const(1)

# ------------------------- Negation, addition, multiplication ---------------

#' minus(x) = -x = 0 - x = sub(0, x).
#' @export
tree_minus <- function(x = "x") Eml(tree_ln(tree_zero()), tree_exp(x))

#' x + y = -((-x) - y) ... but easier: x + y = ln(exp(x) * exp(y))
#' and multiplication itself unrolls. We use:
#'    x + y = -((-x) + (-y) reversed)... too tangled.
#' Cleanest: x + y = sub(x, -y) = eml(ln(x), exp(-y)) where -y is a sub-tree.
#' @export
tree_add <- function(x = "x", y = "y") {
  Eml(tree_ln(x), tree_exp(tree_minus(y)))
}

#' x * y = exp(ln(x) + ln(y)).  We assemble exp() of an addition tree.
#' @export
tree_mul <- function(x = "x", y = "y") {
  add_lnx_lny <- tree_add(tree_ln(x), tree_ln(y))
  tree_exp(add_lnx_lny)
}

#' x / y = exp(ln(x) - ln(y)).
#' @export
tree_div <- function(x = "x", y = "y") {
  sub_lnx_lny <- tree_sub(tree_ln(x), tree_ln(y))
  tree_exp(sub_lnx_lny)
}

#' x ^ y = exp(y * ln(x)).
#' @export
tree_pow <- function(x = "x", y = "y") {
  tree_exp(tree_mul(y, tree_ln(x)))
}

# ------------------------- Trig & special constants -------------------------

#' i = sqrt(-1) = exp(i*pi/2) -- circular. Use ln(-1) = i*pi, then halve.
#' We can construct i from: i = exp(ln(-1)/2). And ln(-1) involves principal
#' branch of complex log -- which our `eml()` implementation uses.
#'
#' Specifically: ln(-1) = tree_ln applied to the *constant* -1.
#' Then i = exp(ln(-1) / 2). To divide by 2, use: x/2 = exp(ln(x) - ln(2)).
#' To get 2: 2 = 1 + 1.
#' @export
tree_two <- function() tree_add(1, 1)

#' Tree for pi.   pi = -i * ln(-1)  (since ln(-1) = i*pi  =>  pi = ln(-1) / i).
#' Equivalently:  pi = Im(ln(-1)) but we don't have an imag-part operator,
#' so we use:    pi = ln(-1) * (-i) = -i * i * pi / i = ...
#' Cleanest: pi^2 = -ln(-1)^2, so pi = sqrt(-ln(-1)^2). But sqrt is also derived.
#' Use: pi = (ln(-1)) / i, with i = exp(ln(-1)/2).
#' @export
tree_pi <- function() {
  ln_neg1 <- tree_ln(tree_neg_one())
  tree_div(ln_neg1, tree_i())
}

#' Tree for i.  i = exp(ln(-1) / 2).
#' @export
tree_i <- function() {
  ln_neg1 <- tree_ln(tree_neg_one())
  half_ln_neg1 <- tree_div(ln_neg1, tree_two())
  tree_exp(half_ln_neg1)
}

#' sin(x) = (exp(i*x) - exp(-i*x)) / (2*i)
#' @export
tree_sin <- function(x = "x") {
  ix      <- tree_mul(tree_i(), x)
  neg_ix  <- tree_minus(ix)
  numer   <- tree_sub(tree_exp(ix), tree_exp(neg_ix))
  denom   <- tree_mul(tree_two(), tree_i())
  tree_div(numer, denom)
}

#' cos(x) = (exp(i*x) + exp(-i*x)) / 2
#' @export
tree_cos <- function(x = "x") {
  ix     <- tree_mul(tree_i(), x)
  neg_ix <- tree_minus(ix)
  numer  <- tree_add(tree_exp(ix), tree_exp(neg_ix))
  tree_div(numer, tree_two())
}

#' sqrt(x) = x ^ (1/2). 1/2 we build as tree_div(1, 2).
#' @export
tree_sqrt <- function(x = "x") {
  half <- tree_div(1, tree_two())
  tree_pow(x, half)
}

# ------------------------- Sanity catalog -----------------------------------

#' A named list of all standard identities, for testing & demos.
#' @export
eml_catalog <- function() {
  list(
    one     = tree_one(),
    e       = tree_e(),
    zero    = tree_zero(),
    neg_one = tree_neg_one(),
    two     = tree_two(),
    i       = tree_i(),
    pi      = tree_pi(),
    exp     = tree_exp("x"),
    ln      = tree_ln("x"),
    minus   = tree_minus("x"),
    add     = tree_add("x", "y"),
    sub     = tree_sub("x", "y"),
    mul     = tree_mul("x", "y"),
    div     = tree_div("x", "y"),
    pow     = tree_pow("x", "y"),
    sqrt    = tree_sqrt("x"),
    sin     = tree_sin("x"),
    cos     = tree_cos("x")
  )
}
