# tools/build_logo.R
#
# Reproducible hex sticker for emlR. Run once; output is committed to
# `man/figures/logo.png`. Not invoked at install or check time.
#
# Required packages (build-only, intentionally NOT in DESCRIPTION):
#   ggplot2, ggforce, ambient, ggtext, ggfx, grid, ragg
#
# Run:
#   Rscript tools/build_logo.R
#
# Output:
#   man/figures/logo.png   — 600 x 696 px, hex point-up, indigo→cyan

suppressPackageStartupMessages({
  library(ggplot2)
  library(ggforce)
  library(ambient)
  library(ggtext)
  library(ggfx)
  library(grid)
})

set.seed(2603)  # arXiv prefix of Odrzywolek (2026)

# ---- hex geometry ---------------------------------------------------------
# The hex stroke itself is drawn by ggforce::geom_regon() further below.
# `inside_hex()` (defined after the noise grid) is the data-side predicate
# used to clip the perlin raster — that is filtering, not graphics, and is
# kept hand-written for transparency.

# ---- background: ambient perlin noise raster, hex-clipped ----------------
grid_n <- 400
noise_grid <- long_grid(
  x = seq(-sqrt(3)/2, sqrt(3)/2, length.out = grid_n),
  y = seq(-1,         1,         length.out = grid_n)
)
noise_grid$value <- gen_perlin(
  noise_grid$x, noise_grid$y,
  frequency = 1.4, seed = 2603
) +
  0.6 * gen_perlin(
    noise_grid$x, noise_grid$y,
    frequency = 4.0, seed = 2026
  )

# Drop pixels outside the hex (point-in-polygon via simple bound test on
# the six hex edges — equivalent to abs(x) <= sqrt(3)/2 AND
# abs(y) + abs(x)/sqrt(3) <= 1 for a point-up regular hex).
inside_hex <- function(x, y) {
  abs(x) <= sqrt(3) / 2 + 1e-9 &
    abs(y) + abs(x) / sqrt(3) <= 1 + 1e-9
}
noise_grid <- noise_grid[inside_hex(noise_grid$x, noise_grid$y), ]

# ---- exp / log overlay curves --------------------------------------------
curve_x <- seq(-1.2, 1.2, length.out = 400)
exp_curve <- data.frame(
  x = curve_x,
  y = (exp(curve_x) - 1) / 3   # rescaled so it fits the hex
)
log_curve <- data.frame(
  x = curve_x[curve_x > 0.05],
  y = log(curve_x[curve_x > 0.05]) / 3
)
exp_curve <- exp_curve[inside_hex(exp_curve$x, exp_curve$y), ]
log_curve <- log_curve[inside_hex(log_curve$x, log_curve$y), ]

# ---- palette --------------------------------------------------------------
pal_low  <- "#0b1e3f"  # deep indigo
pal_mid  <- "#1e4a8a"  # mid blue
pal_high <- "#7ad8ff"  # cyan

# ---- plot ----------------------------------------------------------------
p <- ggplot() +
  # Hex-clipped noise background. ggfx::with_mask would also work; using
  # geom_raster on already-clipped data keeps the dependency surface small.
  geom_raster(
    data = noise_grid,
    aes(x, y, fill = value),
    interpolate = TRUE,
    show.legend = FALSE
  ) +
  scale_fill_gradientn(colours = c(pal_low, pal_mid, pal_high)) +
  # Subtle exp / log curves (low alpha provides the soft look without blur)
  geom_path(
    data = exp_curve,
    aes(x, y),
    colour = "white",
    alpha  = 0.30,
    linewidth = 0.7
  ) +
  geom_path(
    data = log_curve,
    aes(x, y),
    colour = "white",
    alpha  = 0.30,
    linewidth = 0.7
  ) +
  # Glowing formula at the centre — three lines so the full identity
  # `eml(x, y) = e^x - ln y` is legible on the sticker, with `=` on
  # its own line as a visual hinge between definiendum and definiens.
  with_outer_glow(
    geom_richtext(
      aes(x = 0, y = 0.10),
      label = paste0(
        "eml(x,&thinsp;y)<br>",
        "=<br>",
        "e<sup>x</sup> &minus; ln&thinsp;y"
      ),
      colour = "white",
      fill   = NA,
      label.colour = NA,
      family = "sans",
      size   = 6.5,
      fontface = "bold",
      lineheight = 1.0
    ),
    colour = pal_high,
    sigma  = 8,
    expand = 6
  ) +
  # Wordmark
  with_outer_glow(
    geom_richtext(
      aes(x = 0, y = -0.70),
      label = "**emlR**",
      colour = "white",
      fill   = NA,
      label.colour = NA,
      family = "sans",
      size   = 7
    ),
    colour = pal_high,
    sigma  = 6,
    expand = 4
  ) +
  # Hex frame stroke — native ggforce regular-polygon primitive. ggforce
  # places a vertex at angle `angle` (default = 0 ⇒ vertex at 3 o'clock,
  # i.e. flat-top with vertices left/right). Adding pi/2 rotates by 90°
  # to put the vertex at 12 o'clock (point-up) so the stroke aligns with
  # the `inside_hex()` predicate that clips the perlin raster.
  geom_regon(
    aes(x0 = 0, y0 = 0, r = 1, sides = 6, angle = pi / 2),
    fill   = NA,
    colour = "white",
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

message("wrote ", out_path, " (",
        format(file.size(out_path), big.mark = ","), " bytes)")
