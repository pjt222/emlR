# --- 4a. match_eml -----------------------------------------------------------

test_that("match_eml: literal-vs-literal match returns empty bindings", {
  expect_identical(match_eml(1, 1), list())
  expect_identical(match_eml(quote(x), quote(x)), list())
})

test_that("match_eml: literal-vs-mismatched-literal returns NULL", {
  expect_null(match_eml(1, 2))
  expect_null(match_eml(quote(x), quote(y)))
})

test_that("match_eml: simple metavar binds", {
  out <- match_eml(quote(x), quote(`_a`))
  expect_equal(out, list(`_a` = quote(x)))

  out <- match_eml(quote(eml(1, x)), quote(eml(1, `_x`)))
  expect_equal(out, list(`_x` = quote(x)))
})

test_that("match_eml: shape mismatch returns NULL", {
  expect_null(match_eml(quote(eml(1, x)), quote(eml(`_x`, 1))))
  expect_null(match_eml(quote(eml(1, x)), quote(exp(`_x`))))
  expect_null(match_eml(1, quote(eml(`_x`, 1))))
})

test_that("match_eml: linear repeated metavar binding", {
  out <- match_eml(quote(eml(x, x)), quote(eml(`_x`, `_x`)))
  expect_equal(out, list(`_x` = quote(x)))

  expect_null(match_eml(quote(eml(x, y)), quote(eml(`_x`, `_x`))))
})

test_that("match_eml: nested patterns", {
  out <- match_eml(quote(eml(eml(1, x), 1)),
                   quote(eml(eml(1, `_a`), 1)))
  expect_equal(out, list(`_a` = quote(x)))

  # The whole paper-Eq.5 shape
  out <- match_eml(quote(eml(1, eml(eml(1, y), 1))),
                   quote(eml(1, eml(eml(1, `_x`), 1))))
  expect_equal(out, list(`_x` = quote(y)))
})

test_that("match_eml: pattern with named function symbol", {
  out <- match_eml(quote(eml(log(a), exp(b))),
                   quote(eml(log(`_x`), exp(`_y`))))
  expect_equal(out, list(`_x` = quote(a), `_y` = quote(b)))
})

# --- 4b. simplify_eml --------------------------------------------------------

test_that("simplify_eml folds constant-only expressions", {
  # eml(1, 1) = e
  out <- simplify_eml(quote(eml(1, 1)))
  expect_true(is.complex(out) || is.numeric(out))
  expect_equal(Re(out), exp(1), tolerance = 1e-12)
})

test_that("simplify_eml leaves expressions with free variables", {
  expect_identical(simplify_eml(quote(eml(x, 1))), quote(eml(x, 1)))
  expect_identical(simplify_eml(quote(eml(1, eml(eml(1, x), 1)))),
                   quote(eml(1, eml(eml(1, x), 1))))
})

test_that("simplify_eml folds constant subtrees inside variable contexts", {
  # eml(x, eml(1, 1)) -> eml(x, e)
  out <- simplify_eml(quote(eml(x, eml(1, 1))))
  expect_true(is.call(out))
  expect_identical(out[[1L]], as.name("eml"))
  expect_identical(out[[2L]], quote(x))
  expect_equal(Re(out[[3L]]), exp(1), tolerance = 1e-12)
})

test_that("simplify_eml is idempotent", {
  inputs <- list(
    quote(eml(1, 1)),
    quote(eml(x, 1)),
    quote(eml(1, eml(eml(1, x), 1))),
    quote(eml(x, eml(1, 1)))
  )
  for (e in inputs) {
    once  <- simplify_eml(e)
    twice <- simplify_eml(once)
    expect_identical(once, twice)
  }
})

# --- 4c. simplify_native single rules ---------------------------------------

test_that("N1: eml(_x, 1) -> exp(_x)", {
  expect_identical(simplify_native(quote(eml(x, 1))), quote(exp(x)))
  expect_identical(simplify_native(quote(eml(y, 1))), quote(exp(y)))
})

test_that("N2: eml(1, 1) -> exp(1) (folded to numeric e)", {
  out <- simplify_native(quote(eml(1, 1)))
  # After fold: complex/numeric e
  expect_true(is.complex(out) || is.numeric(out))
  expect_equal(Re(out), exp(1), tolerance = 1e-12)
})

test_that("N3: eml(1, eml(eml(1, _x), 1)) -> log(_x)  [headline]", {
  expect_identical(simplify_native(quote(eml(1, eml(eml(1, x), 1)))),
                   quote(log(x)))
})

test_that("N4: eml(log(_x), exp(_y)) -> _x - _y", {
  expect_identical(simplify_native(quote(eml(log(a), exp(b)))),
                   quote(a - b))
})

test_that("N5: eml(log(_x), 1) -> _x", {
  expect_identical(simplify_native(quote(eml(log(x), 1))),
                   quote(x))
})

test_that("simplify_native is idempotent on the headline forms", {
  inputs <- list(
    quote(eml(x, 1)),
    quote(eml(1, eml(eml(1, x), 1))),
    quote(eml(log(a), exp(b))),
    quote(eml(log(x), 1))
  )
  for (e in inputs) {
    once  <- simplify_native(e)
    twice <- simplify_native(once)
    expect_identical(once, twice)
  }
})
