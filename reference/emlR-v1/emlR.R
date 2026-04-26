# =============================================================================
#  emlR -- single-file loader
#
#  Source this file to load the full library:
#     source("emlR.R")
#
#  Or load the package by sourcing each file in R/.
# =============================================================================

local({
  here <- if (exists("emlR_dir")) emlR_dir else dirname(sys.frame(1)$ofile %||% ".")
  files <- c("R/01_core.R", "R/02_tree_ops.R", "R/03_identities.R", "R/04_master.R")
  for (f in files) {
    p <- file.path(here, f)
    if (file.exists(p)) source(p, local = FALSE)
  }
})

# Fallback infix used above
`%||%` <- function(a, b) if (!is.null(a)) a else b
