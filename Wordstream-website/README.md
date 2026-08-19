# Wordstream — website

The marketing site for [Wordstream](../Wordstream), the open-source local dictation
app for macOS. Astro, static output, no client framework.

## The design system

This site is a port of the app's design system, not a separate look. The two are
meant to stay in step:

| Website                   | App                                 |
| ------------------------- | ----------------------------------- |
| `src/styles/tokens.css`   | `Wordstream/DesignSystem/Tokens.swift`     |
| `src/styles/global.css`   | `Wordstream/DesignSystem/Typography.swift` |
| `src/styles/components.css` | `Wordstream/DesignSystem/Components.swift` |
| `src/lib/motif.ts`        | `Wordstream/DesignSystem/Motif.swift`      |

If you change a token, a type style, or the motif geometry in one, change it in
the other.

### Colour has three layers

1. **Palette** — the swappable pastel theme (`--palette-*`)
2. **Primitive** — neutrals and status hues (`--n-*`, `--status-*`)
3. **Semantic** — `--bg-*`, `--fg-*`, `--border-*`, `--focus-ring`

Components may only touch layer 3. Swift enforces that with `private`; here it is
a convention, and the one sanctioned exception is `src/lib/palettes.ts`, which
reads layer 1 so the palette picker can show a swatch before the theme is
applied. Both the palette switch and the dark theme are a swap of layer 3 and
nothing else.

### Gradients

The budget for the whole system is two. This page spends one, on the motif's
lit-from-above material — which is a material, not a decoration. There is no
page-level hero gradient, matching the app's onboarding, which is entitled to one
and declines it.

### Fonts

Instrument Serif, Plus Jakarta Sans and JetBrains Mono, self-hosted from
`public/fonts/` — the same OFL files the app bundles in
`Wordstream/Resources/Fonts/`.

## Development

```bash
npm install
npm run dev
```

```bash
npm run build
```

Output goes to `dist/` as static HTML.

## Before you ship

`src/lib/site.ts` holds the repository URL, the releases link and the stated
requirements. Point them at the real repository — they are currently a
placeholder under `ParikshithV/Wordstream`.
