test_that("compile_eml produces the expected ops/args for the K=7 log expr", {
  bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
  # Post-order: LIT, LIT, VAR, EML, LIT, EML, EML
  expect_equal(bc$ops,  c(0L, 0L, 1L, 2L, 0L, 2L, 2L))
  expect_equal(bc$args, c(1L, 1L, 1L, 0L, 1L, 0L, 0L))
  expect_equal(bc$consts, 1 + 0i)
  expect_equal(bc$vars,   "x")
  expect_equal(length(bc$ops), eml_K(bc$source))
})

test_that("compile_eml deduplicates the constants pool", {
  bc <- compile_eml(quote(eml(1, eml(1, x))))
  expect_equal(length(bc$consts), 1L)
  expect_equal(bc$consts, 1 + 0i)
  # Both LITs must point to const idx 1
  lit_args <- bc$args[bc$ops == 0L]
  expect_true(all(lit_args == 1L))
})

test_that("compile_eml records max_stack equal to right-deep tree depth", {
  # ln(x) right-deep K=7 — peak sp during execution = 3
  bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
  expect_equal(bc$max_stack, 3L)

  # Single eml node: peak = 2
  expect_equal(compile_eml(quote(eml(x, 1)))$max_stack, 2L)

  # Bare leaf: peak = 1
  expect_equal(compile_eml(1)$max_stack, 1L)
})

test_that("run_bytecode equals eml_eval on representative cases", {
  cases <- list(
    list(expr = quote(eml(1, 1)),                       vars = list()),
    list(expr = quote(eml(x, 1)),                       vars = list(x = 0.5)),
    list(expr = quote(eml(1, eml(eml(1, x), 1))),       vars = list(x = 2)),
    list(expr = quote(eml(1, eml(eml(1, x), 1))),
         vars = list(x = c(0.5, 1, 2, 3, 5)))
  )
  for (cs in cases) {
    bc <- compile_eml(cs$expr)
    v_eval <- eml_eval(cs$expr, cs$vars)
    v_bc   <- run_bytecode(bc, cs$vars)
    expect_equal(v_bc, v_eval, tolerance = 1e-12)
  }
})

test_that("run_bytecode is vectorised over input bindings", {
  xs <- seq(0.5, 5, length.out = 50)
  bc <- compile_eml(quote(eml(1, eml(eml(1, x), 1))))
  out <- run_bytecode(bc, list(x = xs))
  expect_equal(Re(out), log(xs), tolerance = 1e-10)
  expect_equal(length(out), length(xs))
})

test_that("run_bytecode errors on missing variable", {
  bc <- compile_eml(quote(eml(x, 1)))
  expect_error(run_bytecode(bc, list()), "missing variable")
})

# Random-tree generator and equivalence test (SPEC §4.5)
random_eml_tree <- function(max_depth, var_names = c("x", "y")) {
  if (max_depth == 0 || runif(1) < 0.4) {
    if (runif(1) < 0.5) {
      return(sample(c(1, 1, 1, 0.5, 2), 1))   # bias toward 1
    } else {
      return(as.name(sample(var_names, 1)))
    }
  }
  call("eml",
       random_eml_tree(max_depth - 1, var_names),
       random_eml_tree(max_depth - 1, var_names))
}

test_that("run_bytecode == eml_eval on 100 random trees", {
  set.seed(20260426)
  agree <- TRUE
  for (i in seq_len(100)) {
    expr <- random_eml_tree(sample.int(5, 1))
    vars <- list(x = runif(20, 0.1, 5),
                 y = runif(20, 0.1, 5))
    v_eval <- eml_eval(expr, vars)
    v_bc   <- run_bytecode(compile_eml(expr), vars)
    if (!isTRUE(all.equal(v_bc, v_eval, tolerance = 1e-10))) {
      agree <- FALSE
      break
    }
  }
  expect_true(agree)
})
