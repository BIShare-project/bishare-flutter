# Roadmap

Where BIShare is headed. This is a living document — ideas and priorities shift,
and **community input is very welcome**. Open an issue or a discussion to propose
something, or grab a [`help wanted`](https://github.com/BIShare-project/bishare-flutter/labels/help%20wanted)
item.

> Status legend: ✅ shipped · 🔜 planned · 🧪 exploring · 💡 idea

## Recently shipped ✅

- **QR Beam** — offline file transfer over an animated stream of QR codes (no
  network at all).
- **Open source** — the client is now MIT-licensed and public.
- **Cross-platform** — one codebase on iOS, Android, macOS, Windows, Linux.
- **End-to-end encryption** — X25519 + AES-256-GCM with per-file keys.

## Near-term 🔜

- **Folder Sync** *(coming soon)* — keep folders in sync across your own devices,
  local-first and end-to-end encrypted.
- **Desktop polish** — camera support for QR Beam on Linux, window/tray niceties,
  packaging & signing for Windows/macOS/Linux.
- **Transfer resume** — make interrupted transfers resume more robustly.
- **Accessibility pass** — semantics labels, focus order, and screen-reader
  support across all screens.
- **More languages** — see [docs/TRANSLATIONS.md](docs/TRANSLATIONS.md).

## Exploring 🧪

- **QUIC transport** — a faster, multiplexed transport via `quinn` (Rust) for
  large transfers and lossy networks.
- **Over-the-air translations** — ship translation fixes without an app update
  (bundled base + a cached remote overlay).

## Ideas 💡

- **Air Gesture** — send with a hand gesture (grab → throw → catch) using
  on-device hand tracking. Feasibility notes exist; not committed.
- **Broadcast / one-to-many** transfers.

## How to influence the roadmap

- 👍 an existing issue to signal demand.
- 💬 start a [Discussion](https://github.com/BIShare-project/bishare-flutter/discussions)
  for bigger ideas.
- 🛠️ pick up a `help wanted` item — see [CONTRIBUTING.md](CONTRIBUTING.md).
