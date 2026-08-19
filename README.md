# Wordstream

**Dictation that stays on your Mac.**

Wordstream is an open-source dictation app for macOS and an alternative to Wispr
Flow. Hold a key, talk, and your words land where your cursor is — transcribed by
Whisper running locally on the Neural Engine, cleaned up by whichever model you
choose, with every parameter in the open.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS%20·%20Apple%20silicon-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20·%20SwiftData-orange.svg)

- **Audio never leaves the Mac.** There is no cloud transcription path in the app at all.
- **Swap any model.** Every WhisperKit variant, and your pick of cleanup engine and model ID.
- **No account.** No sign-in, no subscription, no telemetry, no analytics, no crash reporting.

---

## Contents

- [How it works](#how-it-works)
- [Speech model](#speech-model)
- [Cleanup](#cleanup)
- [What you can change](#what-you-can-change)
- [Privacy](#privacy)
- [Install](#install)
- [Build from source](#build-from-source)
- [Permissions](#permissions)
- [Repository layout](#repository-layout)
- [Contributing](#contributing)
- [FAQ](#faq)
- [License](#license)

---

## How it works

Four steps, and you only perform the first one.

1. **Hold your key.** Right Option by default, or any key or chord you record
   yourself. Double-tap it for hands-free if you would rather not hold anything.
   Escape while recording cancels.
2. **Whisper listens, on this Mac.** Audio goes to a Whisper model running locally
   on the Neural Engine through WhisperKit. Turn on live preview and you watch the
   words arrive in the overlay as you speak.
3. **Cleanup turns speech into writing.** Filler words go, self-corrections are
   applied, punctuation and capitalisation are fixed. You choose which engine does
   it — including one that never leaves the machine.
4. **The text lands at your cursor.** Pasted with the clipboard restored
   afterwards, or written straight into the focused field through the
   Accessibility API. Whichever you pick, it works in Electron apps too.

## Speech model

Whisper runs entirely on this Mac. Nothing you dictate is uploaded during
transcription.

- **Every WhisperKit variant, in a list.** `tiny` through `large-v3`, plus the
  distilled and turbo builds, downloaded on demand with real progress rather than
  an indeterminate spinner. The variant Argmax recommends for your specific Mac is
  pre-selected, so choosing one is never a blocking step.
- **Measured, not guessed.** After a model loads, Wordstream runs one warm-up pass
  and reports how many seconds of audio it processes per second of wall clock on
  *your* hardware (e.g. `6.4× real time · large-v3-turbo`). Below about 1× the live
  preview will lag your voice, and the app says so instead of leaving you to wonder.

## Cleanup

Rule-based cleanup always runs. A language model on top of it removes filler
words, applies your self-corrections, and fixes punctuation — and you choose which
model, including none.

| Tier | Where it runs | What it is |
| --- | --- | --- |
| **Automatic** *(default)* | Best available | Picks the best tier this Mac can actually run right now, and falls back quietly when one becomes unavailable. |
| **Apple Intelligence** | On device | The system Foundation Models framework. No download, no key, nothing leaves the Mac. Needs a Mac with Apple Intelligence enabled. |
| **Local model (MLX)** | On device | A small instruction-tuned model on this Mac's GPU through MLX — `mlx-community/gemma-3-1b-it-qat-4bit` by default, or any MLX-community model ID you paste in. |
| **Cloud** | Leaves the Mac | Off unless you add an API key, which is stored in the Keychain. Anthropic or OpenAI. Only the transcribed text is sent — never the audio — and only for this step. |
| **Rules only** | On device | No language model at all. Deterministic cleanup: filler removal, spoken punctuation, spacing, capitalisation, your dictionary. |

### Style

Independent of which engine runs it. The prompt is deliberately narrow: the
failure mode for a dictation cleaner is not a clumsy rewrite, it is the model
deciding your transcript was a question and answering it.

| Style | What it does |
| --- | --- |
| Verbatim | Change as little as possible — clear errors and sentence-ending punctuation only. |
| Clean up | Drop fillers and false starts, apply self-corrections, keep your own words and tone. |
| Polished | Tighten into clear prose while preserving meaning and register. |
| Email | A short, well-punctuated email body. No greeting or sign-off you did not dictate. |
| Bullets | A concise bulleted list, one idea per bullet. |

## What you can change

Not an exhaustive list because it is a short one — an exhaustive list because
there is nothing hidden behind it.

| Setting | |
| --- | --- |
| Speech model | Any Whisper variant WhisperKit offers, from tiny to large-v3. |
| Spoken language | Pin a language instead of auto-detecting. Far more reliable on a two-second utterance. |
| Live preview | Stream text into the overlay while you talk. Costs inference as you speak; the inserted text always comes from the final pass. |
| Dictation key | Record any shortcut. Conflicts with macOS's own dictation and the emoji picker are flagged, with the fix. |
| Command mode key | A second, separate shortcut, so dictating an instruction and dictating prose need not share a trigger. |
| Insertion mode | Paste-and-restore, or write directly through the Accessibility API. The direct path falls back to paste when an app ignores it. |
| Filler removal | Drop standalone "um", "uh", "er" — independently of whichever cleanup tier is running. |
| Spoken punctuation | Turn "period", "comma" and "new line" into the punctuation itself. |
| Custom dictionary | Map what you say to what should be written. Names, product spellings, internal jargon. |
| App awareness | The cleanup prompt shifts by target app: terse and literal in a terminal, complete sentences in a mail composer. |
| History | Every dictation kept locally in SwiftData, searchable, copyable, deletable. |
| Appearance | Six palettes and a light/dark switch. |

## Privacy

Stated as a rule rather than a promise, because the code is right there.

**Never leaves your Mac**

- Your audio. There is no cloud transcription path in the app.
- Your dictation history, kept locally in SwiftData.
- Your custom dictionary.
- Your settings, shortcuts and palette.
- Anything at all, if you leave the Cloud tier off — which is the default.

**Only if you opt in**

- The transcribed *text*, sent to the cleanup provider you pick.
- Requires an API key you supply, stored in the macOS Keychain.
- Never the audio, and never anything else in the app.
- Model weights, downloaded once from Hugging Face.

No account, no sign-in, no telemetry, no analytics, no crash reporting service.
The app makes no network request you did not ask for.

## Install

Download the latest signed build from
[Releases](https://github.com/ParikshithV/Wordstream/releases/latest). On first
launch it walks you through the three permissions and picks a speech model for
your machine.

**Requirements:** macOS 26.3 or later, Apple silicon. The Apple Intelligence
cleanup tier additionally needs a Mac with Apple Intelligence enabled; every other
tier works without it.

## Build from source

```bash
git clone https://github.com/ParikshithV/Wordstream.git
cd Wordstream
open Wordstream.xcodeproj
```

Hit run. Swift package dependencies resolve on first build — there is no
CocoaPods, Carthage or Homebrew step.

Requires Xcode 26 or later. The app is deliberately **not sandboxed**: it installs
a `CGEventTap`, reads and writes other apps' text through the Accessibility API,
and posts a synthetic ⌘V, none of which is possible inside the App Sandbox.
Hardened Runtime is on, and `com.apple.security.app-sandbox` is visibly absent
from [`Wordstream.entitlements`](Wordstream.entitlements) — adding an entitlement
must not quietly reintroduce it.

### Dependencies

| Package | Used for |
| --- | --- |
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) | On-device Whisper transcription and streaming |
| [mlx-swift](https://github.com/ml-explore/mlx-swift), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | Local LLM cleanup on the GPU |
| [swift-transformers](https://github.com/huggingface/swift-transformers), [swift-huggingface](https://github.com/huggingface/swift-huggingface) | Tokenisers and model downloads |
| [EventSource](https://github.com/mattt/EventSource) | Streaming responses from cloud providers |

## Permissions

macOS asks for each of these separately, and each fails silently on its own, so
the app checks all three rather than assuming.

| Permission | Why |
| --- | --- |
| **Microphone** | To hear you. |
| **Accessibility** | To place text into other apps. |
| **Input Monitoring** | To notice your dictation key while another app is in front. |

## Repository layout

```
Wordstream/
├── App/              AppDelegate and DictationCoordinator — the state machine
│                     that turns a held key into text in someone else's app
├── Input/            Hotkey monitoring (CGEventTap), shortcut recording, text injection
├── Transcription/    WhisperKit engine and the speech-model catalogue
├── Enhancement/      Cleanup pipeline: rules, Foundation Models, MLX, cloud
├── Overlay/          The floating recording panel
├── UI/               Settings, onboarding, history, dictionary, menu bar
├── Models/           Preferences and the SwiftData Transcript model
├── Permissions/      The three-permission checker
├── DesignSystem/     Tokens, typography, components, motif
└── Support/          Keychain wrapper

Wordstream-website/   Astro marketing site (see its own README)
```

### Design system

The website is a port of the app's design system, not a separate look. The two are
meant to stay in step — if you change a token, a type style or the motif geometry
in one, change it in the other.

| App | Website |
| --- | --- |
| `Wordstream/DesignSystem/Tokens.swift` | `Wordstream-website/src/styles/tokens.css` |
| `Wordstream/DesignSystem/Typography.swift` | `Wordstream-website/src/styles/global.css` |
| `Wordstream/DesignSystem/Components.swift` | `Wordstream-website/src/styles/components.css` |
| `Wordstream/DesignSystem/Motif.swift` | `Wordstream-website/src/lib/motif.ts` |

Colour has three layers — palette (`--palette-*`), primitive (`--n-*`,
`--status-*`) and semantic (`--bg-*`, `--fg-*`, `--border-*`). Components may only
touch the semantic layer; Swift enforces that with `private`, and on the web it is
a convention. Both the palette switch and the dark theme are a swap of the
semantic layer and nothing else.

### Website

```bash
cd Wordstream-website
npm install
npm run dev
```

`npm run build` emits static HTML to `dist/`. Requires Node 22.12 or later.

## Contributing

Issues and pull requests are welcome at
[github.com/ParikshithV/Wordstream](https://github.com/ParikshithV/Wordstream/issues).

- Match the surrounding style. The codebase comments the *why*, not the *what* —
  read a neighbouring file before adding a new one.
- Keep the app's privacy rule intact: audio never leaves the Mac, and nothing goes
  over the network unless the user deliberately turned that tier on.
- Design-system changes belong in both the app and the website (see the table
  above).
- If a change affects what the app sends, receives, or asks permission for, say so
  in the pull request description.

## FAQ

**Does my audio ever leave the Mac?**
No. Transcription is always local — there is no cloud transcription path in the
app at all. The only thing that can be sent anywhere is the already-transcribed
text, and only if you have deliberately chosen the Cloud cleanup tier and added
your own API key.

**Why does it need three permissions?**
Microphone to hear you, Accessibility to place text into other apps, and Input
Monitoring to notice your dictation key while another app is in front. macOS asks
for each separately, and each fails silently on its own.

**Why is it not sandboxed?**
It installs a `CGEventTap`, reads and writes other apps' text through the
Accessibility API, and posts a synthetic ⌘V. None of that is possible inside the
App Sandbox. Hardened Runtime is on; the sandbox is deliberately, and visibly,
absent from the entitlements file.

**Does it work in VS Code, Slack, and other Electron apps?**
Yes — that is why paste-and-restore is the default insertion mode. The
Accessibility API path is cleaner but silently does nothing in some apps, so it
falls back to paste when that happens.

**How big is the model download?**
It depends which Whisper variant you choose, from tens of megabytes to well over a
gigabyte. The download shows real progress rather than an indeterminate spinner,
and the app measures how fast the model actually runs on your Mac afterwards so
you can judge whether to go smaller.

**What does it cost?**
Nothing. It is MIT-licensed and there is no account, no subscription, and no
telemetry. If you turn on the optional Cloud cleanup tier, you pay your own
provider directly with your own key.

## License

MIT. See [LICENSE](LICENSE).
