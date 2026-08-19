/*
 * motif.ts
 * Wordstream
 *
 * The Wordstream mark's geometry, ported from the app's Motif.swift.
 *
 * One mark, one drawing: three concentric rosette rings stroked at a single
 * medium weight, at every size on every surface. Keep `MOTIF_RINGS` and
 * `markStrokeWidth` in step with `MotifMark` in Motif.swift — they are the same
 * mark, and the app and the site are looked at side by side.
 *
 * Geometry is never eyeballed: everything derives from circles repeated on a
 * shared ring, generated from the two ratios the system calls out — cusp 0.93,
 * and lobe counts that share no divisors — rather than from copied path data,
 * so it stays reproducible at any size.
 */

/**
 * The union of `lobes` circles repeated on a shared ring: broad outward lobes
 * separated by small sharp cusps.
 *
 * Solving for the arc radius, given the cusp ring `rCusp = rOut * cuspRatio`:
 *
 *     h = rCusp·sin(π/n)          half-chord between adjacent cusps
 *     m = rCusp·cos(π/n)          centre → chord midpoint
 *     k = rOut - m                sagitta, how far the lobe bulges past the chord
 *     r = (h² + k²) / 2k          the arc radius that hits rOut at its apex
 *
 * Each arc's centre then sits at `rOut - r` from the middle, along the bisector.
 * Checked against the reference mark: for 16 lobes at rOut 108.01 this yields
 * r = 24.96 against the file's 24.97.
 */
export function rosettePath(
  cx: number,
  cy: number,
  rOut: number,
  lobes: number,
  rotationDeg = -90,
  /**
   * Notch depth between lobes. Deeper turns the mark into a spiky star; the
   * system pins it at 0.93 because with few layers each ring is fully exposed
   * and adjacent scallops otherwise collide into a berry texture.
   */
  cuspRatio = 0.93,
): string {
  const n = Math.max(3, Math.round(lobes));
  const rCusp = rOut * cuspRatio;
  const step = (2 * Math.PI) / n;
  const h = rCusp * Math.sin(step / 2);
  const m = rCusp * Math.cos(step / 2);
  const k = rOut - m;
  if (k <= 0.0001) return '';
  const r = (h * h + k * k) / (2 * k);
  const dC = rOut - r;

  const point = (angle: number, radius: number) => ({
    x: cx + radius * Math.cos(angle),
    y: cy + radius * Math.sin(angle),
  });

  const base = (rotationDeg * Math.PI) / 180;
  const start = point(base, rCusp);
  let d = `M ${f(start.x)} ${f(start.y)}`;

  for (let i = 0; i < n; i++) {
    const a1 = base + step * (i + 1);
    const p1 = point(a1, rCusp);
    // Each lobe is a single minor arc bulging outward — sweep 1, large-arc 0.
    d += ` A ${f(r)} ${f(r)} 0 0 1 ${f(p1.x)} ${f(p1.y)}`;
  }

  return `${d} Z`;
}

/**
 * The three rings of the mark, at lobe counts that are pairwise coprime so the
 * cusps of one ring never line up radially with another's and snap the mark to
 * a rigid star.
 *
 * This replaced three separate marks — a filled four-ring lotus, an outline
 * ring-and-beads mandala, and a single ogee seed — which between them meant the
 * nav, the footer, the overlay demo and the favicon were four different logos
 * for one app.
 */
export const MOTIF_RINGS: ReadonlyArray<{ lobes: number; scale: number; rotation: number }> = [
  { lobes: 11, scale: 1.0, rotation: -90 },
  { lobes: 9, scale: 0.68, rotation: -81 },
  { lobes: 7, scale: 0.36, rotation: -72 },
];

/**
 * The single stroke weight, in viewBox units, matching the app's `size / 16`.
 * Medium: heavy enough to hold at favicon size, light enough that three rings
 * don't close up into a disc.
 */
export function markStrokeWidth(side: number): number {
  return side / 16;
}

function f(n: number): string {
  return Number(n.toFixed(3)).toString();
}
