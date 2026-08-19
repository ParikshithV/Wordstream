/*
 * palettes.ts
 * Wordstream
 *
 * The palette picker's swatches: both ends of each theme's ramp plus its tinted
 * surface, so the choice is legible before it is applied. This is the one
 * narrow, deliberate window onto layer 1 — the picker genuinely cannot do its
 * job without it. Nothing else on the site may read these values.
 */

export interface PaletteEntry {
  id: string;
  name: string;
  /** The ramp described in one phrase, as the design docs table does. */
  character: string;
  swatch: { rampStart: string; rampEnd: string; soft: string };
}

export const PALETTES: readonly PaletteEntry[] = [
  {
    id: 'dawn',
    name: 'Dawn',
    character: 'Indigo → peach',
    swatch: { rampStart: '#2a27b8', rampEnd: '#e8853f', soft: '#eef0ff' },
  },
  {
    id: 'grove',
    name: 'Grove',
    character: 'Sage → wheat',
    swatch: { rampStart: '#2f5335', rampEnd: '#d9a441', soft: '#edf3ec' },
  },
  {
    id: 'blush',
    name: 'Blush',
    character: 'Dusty rose → apricot',
    swatch: { rampStart: '#87304f', rampEnd: '#e58b62', soft: '#fbedf1' },
  },
  {
    id: 'lagoon',
    name: 'Lagoon',
    character: 'Deep teal → sand',
    swatch: { rampStart: '#1f5359', rampEnd: '#dfa469', soft: '#e6f1f2' },
  },
  {
    id: 'lilac',
    name: 'Lilac',
    character: 'Lilac → butter',
    swatch: { rampStart: '#523878', rampEnd: '#d9a93f', soft: '#f2edfa' },
  },
  {
    id: 'clay',
    name: 'Clay',
    character: 'Terracotta → sky',
    swatch: { rampStart: '#853f27', rampEnd: '#5e8ca6', soft: '#faede7' },
  },
];
