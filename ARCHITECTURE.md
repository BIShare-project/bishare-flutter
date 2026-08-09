# Architecture

A quick map of how BIShare is put together, so you can find your way around
before contributing. TL;DR: **Flutter for everything UI**, a small **Rust core**
for crypto + the wire protocol, and a few transports (LAN, remote link, QR Beam).

```
┌──────────────────────────────────────────────────────────────────────┐
│  Presentation  ·  lib/features/<feature>/presentation/                 │
│  Pages · Widgets · Cubits (flutter_bloc)   ·   design system: core/ui/ │
└───────────────┬──────────────────────────────────────────────────────┘
                │  context.read<XCubit>() / BlocBuilder
┌───────────────┴──────────────────────────────────────────────────────┐
│  Feature logic  ·  lib/features/<feature>/{data,domain}/               │
│  services · repositories · plain models                                │
└───────────────┬──────────────────────────────────────────────────────┘
                │  get_it (DI, registered in core/di/locator.dart)
┌───────────────┴──────────────────────────────────────────────────────┐
│  Core services  ·  lib/core/                                           │
│  server/ (receiver)  ·  identity/  ·  storage/ (drift)  ·  rust/ (FFI) │
└───────────────┬──────────────────────────────────────────────────────┘
                │  flutter_rust_bridge
┌───────────────┴──────────────────────────────────────────────────────┐
│  Rust core  ·  rust/  (crate: bishare_ffi + vendored bishare-protocol) │
│  X25519 · AES-256-GCM · binary framing · filename sanitisation         │
└──────────────────────────────────────────────────────────────────────┘
```

## Layers

- **`lib/app/`** — app shell: `router.dart` (go_router), `main_shell.dart` (tab
  shell), bootstrap. Entry point is `lib/main.dart`.
- **`lib/core/`** — cross-cutting services:
  - `ui/` — the design system (`AppCard`, `AppButton`, `AppSheet`, `BiShareQr`, …).
    Import `core/ui/app_ui.dart` to get them all.
  - `server/` — `TransferServer`: the **receiver**, a `shelf` HTTP server. All
    incoming files (LAN, Nearby, QR Beam) funnel through
    `ingestExternalFile(...)` into the shared inbox/history pipeline.
  - `identity/` — device identity, keypair (secure storage), fingerprint.
  - `rust/` — the flutter_rust_bridge facade over the Rust core.
  - `storage/` — `drift` (SQLite): transfer history + favorite devices.
  - `di/` — `get_it` registrations (`locator.dart`).
  - `l10n/` — locales list (`app_locales.dart`).
- **`lib/features/<feature>/`** — feature-first vertical slices, each split into
  `data/` (services), `domain/` (models), `presentation/` (pages, cubits,
  widgets). Notable ones: `send`, `receive`, `nearby`, `qr_beam`, `remote`,
  `room`, `inbox`, `history`, `discovery`, `scanner`, `settings`.
- **`rust/`** — the native crate `bishare_ffi`, exposed to Dart via
  flutter_rust_bridge. It reuses the vendored **`rust/bishare-protocol`** crate
  (crypto + wire format). Generated Dart bindings live in `lib/src/rust/`.

## Transports (how a file actually moves)

- **LAN (same Wi-Fi)** — devices find each other over **mDNS** (`bonsoir`,
  `features/discovery`). The sender (`features/send`, a `dio` client) negotiates
  an X25519 key with the receiver (`TransferServer`, `shelf`), then streams the
  file in **AES-256-GCM chunks** (encrypt/decrypt in the Rust FFI). Nothing
  touches a server.
- **Remote (not nearby)** — `features/remote` produces a link / QR / 6-char code
  the recipient opens in any browser (served by the backend, not in this repo).
- **QR Beam (no network at all)** — `features/qr_beam` encodes a small file as an
  animated stream of QR codes (`domain/beam_codec.dart`) that the other device's
  camera scans and reassembles. The wire format is byte-identical to the web
  implementation.

## State & conventions

- **State:** `flutter_bloc` (Cubit pattern). No Redux/Riverpod.
- **DI:** `get_it` — resolve with `getIt<Service>()`.
- **Routing:** `go_router` (`lib/app/router.dart`) — push full-screen pages with
  `context.push('/route')`.
- **i18n:** `easy_localization` — `'my.key'.tr()`, JSON in `assets/translations/`
  (see [docs/TRANSLATIONS.md](docs/TRANSLATIONS.md)).
- **UI:** `shadcn_ui` primitives wrapped by `core/ui/`.

## Where to start contributing

- **UI / feature tweak** → a `features/<x>/presentation/` file.
- **Transfer / crypto / protocol** → `core/server/`, `features/send/data/`, or the
  Rust crate in `rust/`.
- **Translations** → `assets/translations/` (no build needed).
- Browse [`good first issue`](https://github.com/BIShare-project/bishare-flutter/labels/good%20first%20issue)
  for scoped starting points, and see [CONTRIBUTING.md](CONTRIBUTING.md).
