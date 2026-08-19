/*
 * site.ts
 * Wordstream
 *
 * The handful of facts that appear in more than one place. Change the repo URL
 * and release tag here rather than hunting through the markup.
 */

export const SITE = {
  name: 'Wordstream',
  tagline: 'local dictation for macOS',
  description:
    'Open-source dictation for macOS. Whisper runs on your Mac, cleanup runs where you choose, and every model and parameter is yours to change. A Wispr Flow alternative you can read the source of.',
  repo: 'https://github.com/ParikshithV/Wordstream',
  releases: 'https://github.com/ParikshithV/Wordstream/releases/latest',
  issues: 'https://github.com/ParikshithV/Wordstream/issues',
  license: 'MIT',
  requirements: 'macOS 14 Sonoma or later · Apple silicon',
} as const;
