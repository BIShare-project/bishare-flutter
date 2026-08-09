# Changelog

All notable changes to BIShare are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.4.5] — 2026-08-09

### Added
- **Open source** 🎉 — the BIShare client is now public under the MIT license.
- **QR Beam** — offline file transfer over an animated stream of QR codes, for
  when there's no Wi-Fi, hotspot, or Bluetooth at all (screen → camera). The wire
  format is byte-identical to the web implementation, so any device can beam to
  any other.
- Contributor tooling — a translation completeness checker
  (`dart run tool/check_translations.dart`), guides (`ARCHITECTURE.md`,
  `docs/TRANSLATIONS.md`), issue/PR templates, and CI.

### Notes
- The Rust protocol crate is vendored into `rust/bishare-protocol`, so the app
  builds from a single checkout with no external repo.

---

Earlier history predates the open-source release. From here on, changes will be
noted per release.
