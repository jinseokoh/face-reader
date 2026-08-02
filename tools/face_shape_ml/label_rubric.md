# Face Shape Labeling Rubric (5-class) — v2

Judge ONLY the overall face contour — the outline from forehead sides through
cheeks and jawline to the chin. Ignore hairstyle volume, facial features,
attractiveness, age, and image aesthetics.

## Procedure (follow in order for every image)

1. Trace the visible contour: forehead width, cheek width, jaw width, chin shape.
2. Estimate the length:width ratio numerically — face length (top of forehead
   to chin tip) divided by cheekbone width. State it to yourself before deciding.
3. Check jaw angularity (visible corners?) and chin taper (pointed / rounded / flat).
4. Pick the class whose anchors below fit best.

## Classes with ratio anchors

- **Round** — ratio ≈ 1.0–1.2. Full cheeks, widest at the cheeks, jawline soft
  and curved with no corners, chin short and rounded. Many East Asian faces
  with full cheeks and a short chin are Round even when slightly longer than
  wide — do NOT drift these into Oval.
- **Square** — ratio ≈ 1.0–1.25 with clearly ANGULAR jaw corners; jaw nearly as
  wide as the forehead; chin line flat and wide. Angularity decides, not length.
- **Oval** — ratio ≈ 1.25–1.45 AND a smooth taper: widest at the cheekbones,
  narrowing gently to a rounded chin. Oval requires BOTH clear elongation and
  visible taper. If the face is barely longer than wide → Round; if the sides
  are straight and parallel → Oblong.
- **Oblong** — ratio ≳ 1.45, OR the sides look straight/parallel (forehead ≈
  cheeks ≈ jaw width) with a long mid-face. Length or parallel-sided-ness is
  the dominant impression.
- **Heart** — forehead/cheekbones clearly wider than the jaw; the contour
  narrows sharply to a pointed or narrow chin. Any moderate length qualifies —
  the width contrast decides.

## Tie-breaks

- Round vs Oval → Round when cheeks are full and the chin is short, even if
  slightly elongated. Oval needs unmistakable elongation + taper.
- Oval vs Oblong → Oblong when the sides are straight/parallel or the face is
  very long; Oval when the contour visibly tapers to the chin.
- Long AND angular jaw → Square if the jaw corners dominate; Oblong if the
  length dominates.
- Slightly tapered chin alone is NOT Heart — Heart needs an obviously narrow
  jaw relative to the upper face.

## SKIP rules

Label `SKIP` (with a short reason instead of confidence) when:

- Head is rotated (yaw or pitch) more than slightly off-frontal.
- Jawline or face contour is occluded by hair, hands, thick beard, or collar.
- Extreme expression distorts the jaw (e.g. wide-open laugh).
- Image is too blurry or small to judge the contour.

Do not overuse SKIP — if the contour is judgeable despite minor issues, label
it with `low` confidence instead.

## Confidence

- `high` — clear-cut case.
- `low` — best guess between two plausible classes.
