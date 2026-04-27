# cran-comments.md

## Test environments

* Local: Ubuntu 24.04, R 4.6.0
* GitHub Actions matrix: macOS-latest (R-release), windows-latest
  (R-release), ubuntu-latest (R-devel, R-release, R-oldrel-1)
* `R CMD check --as-cran` locally (clean modulo the LaTeX
  pdflatex tooling, which is not installed on the local machine but
  is on CRAN's check infrastructure)

## R CMD check results

`R CMD check --as-cran` on the source tarball produces:

* 0 errors
* 0 warnings
* 1 NOTE — "New submission". This is the package's first CRAN
  submission.

The local check additionally reports an environment-only ERROR for
PDF manual generation (`pdflatex is not available`) and an
environment-only NOTE for HTML validation (`tidy not found`); both
disappear on CRAN's infrastructure where the LaTeX and HTML
toolchains are present.

## Reverse dependencies

None — first release.

## Submission context

* First CRAN release as 0.1.0.
* The package is an independent R implementation of the EML
  Sheffer operator from Odrzywołek (2026,
  <doi:10.48550/arXiv.2603.21852>).
* License: MIT + file LICENSE.
* Pure base R + Deriv. No compiled code.
* Examples wrap longer-running calls (e.g. `eml_fit()`) in
  `\donttest{}` so they are skipped on CRAN's `--run-donttest`
  pass but available to interactive users.
