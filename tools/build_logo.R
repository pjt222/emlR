# tools/build_logo.R
#
# Reproducible hex sticker for emlR. Run once; output is committed to
# `man/figures/logo.png`. Not invoked at install or check time.
#
# Required packages (build-only, intentionally NOT in DESCRIPTION):
#   ggplot2, ggforce, ggtext, ggfx, grid, ragg
#
# Run:
#   Rscript tools/build_logo.R
#
# Output:
#   man/figures/logo.png   — 600 x 696 px, transparent hex (point-up),
#                            black stroke, white exp/log curves,
#                            cyan-glow `e^x − ln y` formula and **emlR**
#                            wordmark (both tilted 30°).

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggforce)
  library(ggtext)
  library(ggfx)
  library(grid)
})

# ---- hex predicate (curve clipping) --------------------------------------
# The hex stroke itself is drawn by ggforce::geom_regon() further below.
# `inside_hex()` is a point-in-polygon test (simple bound test on the six
# edges — equivalent to abs(x) <= sqrt(3)/2 AND
# abs(y) + abs(x)/sqrt(3) <= 1 for a point-up regular hex). It is used to
# trim the exp/log overlay curves so they do not poke past the hex edge.
inside_hex <- function(x, y) {
  abs(x) <= sqrt(3) / 2 + 1e-9 &
    abs(y) + abs(x) / sqrt(3) <= 1 + 1e-9
}

# ---- exp / log overlay curves --------------------------------------------
curve_x <- seq(-1.2, 1.2, length.out = 400)
exp_curve <- data.frame(
  x = curve_x,
  y = (exp(curve_x) - 2) / 3 # rescaled so it fits the hex
)
log_curve <- data.frame(
  x = curve_x[curve_x > 0.05],
  y = log(curve_x[curve_x > 0.05]) / 3
)
exp_curve <- exp_curve[inside_hex(exp_curve$x, exp_curve$y), ]
log_curve <- log_curve[inside_hex(log_curve$x, log_curve$y), ]

# ---- glow colour ---------------------------------------------------------
pal_high <- "#7ad8ff" # cyan, used by with_outer_glow() on the text layers

# ---- plot ----------------------------------------------------------------
p <- ggplot() +
  # Hex frame fill — native ggforce regular-polygon primitive. ggforce
  # places a vertex at angle `angle` (default = 0 ⇒ vertex at 3 o'clock,
  # i.e. flat-top with vertices left/right). Adding pi/2 rotates by 90°
  # to put the vertex at 12 o'clock (point-up) so the stroke aligns with
  # the `inside_hex()` predicate that trims the overlay curves.
  geom_regon(
    aes(x0 = 0, y0 = 0, r = 1, sides = 6, angle = pi / 2),
    fill = "grey50",
    colour = "black",
    linewidth = 1.6
  ) +
  # Subtle exp / log curves (low alpha provides the soft look without blur)
  geom_path(
    data = exp_curve,
    aes(x, y),
    colour = "white",
    alpha = 0.50,
    linewidth = 0.7
  ) +
  geom_path(
    data = log_curve,
    aes(x, y),
    colour = "white",
    alpha = 0.50,
    linewidth = 0.7
  ) +
  # Glowing single-line formula `e^x − ln y` near the centre, tilted 30°.
  with_outer_glow(
    geom_richtext(
      aes(x = -0.1, y = 0.15),
      label = "e<sup>x</sup> &minus; ln&thinsp;y",
      colour = "white",
      fill = NA,
      label.colour = NA,
      family = "mono",
      size = 7,
      fontface = "bold",
      angle = 30
    ),
    colour = pal_high,
    sigma = 6,
    expand = 2
  ) +
  # Wordmark
  with_outer_glow(
    geom_richtext(
      aes(x = 0.50, y = -0.50),
      label = "**emlR**",
      colour = "white",
      fill = NA,
      label.colour = NA,
      family = "sans",
      fontface = "bold",
      size = 5,
      angle = 30
    ),
    colour = pal_high,
    sigma = 6,
    expand = 2
  ) +
  # Re-stroke the hex on top of the curves and text so the black border is
  # not partially overdrawn.
  geom_regon(
    aes(x0 = 0, y0 = 0, r = 1, sides = 6, angle = pi / 2),
    fill = NA,
    colour = "black",
    linewidth = 1.6
  ) +
  # xlim/ylim are padded beyond the hex bounding box (half-width sqrt(3)/2,
  # half-height 1) so the 1.6mm stroke is not rasterised away at the panel
  # edge. Without this padding the left/right vertices lose ~50% of their
  # stroke width on export.
  coord_fixed(xlim = c(-1.00, 1.00), ylim = c(-1.10, 1.10), expand = FALSE) +
  theme_void() +
  theme(
    plot.background  = element_rect(fill = "transparent", colour = NA),
    panel.background = element_rect(fill = "transparent", colour = NA),
    plot.margin      = margin(0, 0, 0, 0)
  )

# ---- save ----------------------------------------------------------------
out_path <- file.path("man", "figures", "logo.png")
ggsave(
  filename = out_path,
  plot     = p,
  width    = 600,
  height   = 696,
  units    = "px",
  dpi      = 300,
  bg       = "transparent",
  device   = ragg::agg_png
)

message(
  "wrote ", out_path, " (",
  format(file.size(out_path), big.mark = ","), " bytes)"
)
