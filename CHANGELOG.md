# Changelog

All notable changes to BIShare are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **An anonymous "opened today" count.** Once per UTC day the app tells the
  server that an install was opened, and once per thirty days that it is still
  in use, so bishare.app/stats can show active installs. The request carries
  the platform and two true/false flags — no device ID, no fingerprint, nothing
  that lets two pings be joined. It follows the existing *Anonymous usage
  stats* switch in Settings, whose description now says so in all 13 languages.
- **A rating request, at most twice, and only after it has worked.** After the
  third successful transfer the app asks the App Store or Google Play to show
  its own rating dialog; much later (fifteen transfers and 120 days) it may ask
  once more, then never again. A batch of files counts as one transfer, and the
  request waits until the batch has finished. iPhone, iPad, Mac and Android
  only — Windows and Linux have no such dialog and are not touched. Builds that
  did not come from a store (the APK, the DMG) do nothing.

## [2.5.6] — 2026-09-18

### Security
- **Clipboard sync is now encrypted on your network.** Every clipboard datagram
  is sealed to one device with AES-256-GCM, under a key derived from the two
  devices' X25519 keys. Until now it crossed the network as plain text, so
  anything listening on the same Wi-Fi could read what you copied — and, for
  images, could redeem the one-shot pull token before the intended device did.
- **Synced text is only accepted from a device you can see.** The announced
  fingerprint has to belong to a peer discovery currently lists, and the
  datagram has to come from that peer's address. Before this, anything able to
  reach the clipboard port could set your clipboard under any name it chose —
  and a swapped account number or wallet address gets pasted, not read.
- **A clip marked secret is never synced.** Password managers flag what they
  put on the clipboard (`org.nspasteboard.ConcealedType` on macOS,
  `EXTRA_IS_SENSITIVE` on Android) and those clips now stay on the device. iOS
  offers no equivalent flag, so nothing changes there.

### Changed
- Devices advertise their public key over discovery, so sealing a clipboard
  copy costs no extra round trip.

### Breaking
- **Clipboard sync no longer works with 2.5.5 and earlier.** There is
  deliberately no plaintext fallback: one would let anything on the network ask
  for a downgrade by claiming to be an old build. Update both devices. Nothing
  errors in the meantime — older and newer builds simply ignore each other's
  clipboard messages. File transfer, Nearby, Rooms and QR Beam are unaffected.

---

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
