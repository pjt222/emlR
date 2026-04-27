#!/usr/bin/env Rscript
# Regenerate the Mermaid workflow diagram in README.md.
# Invoked locally and by .github/workflows/putior.yaml.

library(putior)

nodes <- put("./R/")
mmd <- put_diagram(nodes, theme = "github", direction = "LR",
                   output = "raw")

readme <- readLines("README.md")
start <- grep("<!-- PUTIOR-WORKFLOW-START -->", readme, fixed = TRUE)
end   <- grep("<!-- PUTIOR-WORKFLOW-END -->",   readme, fixed = TRUE)
stopifnot(length(start) == 1L, length(end) == 1L, end > start)

new_block <- c(
  readme[start],
  "```mermaid",
  strsplit(mmd, "\n", fixed = TRUE)[[1L]],
  "```",
  readme[end]
)

writeLines(
  c(readme[seq_len(start - 1L)],
    new_block,
    if (end < length(readme)) readme[(end + 1L):length(readme)] else character()),
  "README.md"
)

cat(sprintf("README.md regenerated: %d nodes from put('./R/')\n", nrow(nodes)))
