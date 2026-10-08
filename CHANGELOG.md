# Changelog

All notable changes to BIShare are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2.6.1] — 2026-10-08

### Changed
- **The rating request reaches people who use BIShare.** It used to count
  only Wi-Fi transfers, so anyone who mostly sent links, used rooms or
  Nearby was never asked; every kind of transfer counts now (Secure Link,
  live links, rooms, Nearby, browser peers, links opened in the app). The
  first request comes right after the first transfer that works instead of
  the third, and there can be three over time (after 8 transfers and 30 days, and after 20
  transfers and 90 days) instead of two. On iPhone, iPad, Mac and Android it
  is still the system's own dialog, which the system may decide not to show.
- **Windows asks too.** A Microsoft Store install shows a short banner at the
  same moments, with a button to the Store's rating page.
- **"Rate BIShare" in Settings opens the review form.** On iPhone, iPad and
  Mac it now opens the App Store's write-a-review sheet, and on Windows the
  Microsoft Store rating page, instead of the store listing or the website.

## [2.6.0] — 2026-10-07

### Fixed
- **Hindi, Traditional Chinese and Brazilian Portuguese now read as those
  languages.** In Hindi, 234 of the app's 514 strings were French and about 50
  were English; all of them are Hindi now. Traditional Chinese showed about
  half its text in Simplified characters with mainland wording (文件, 设置);
  it now uses Traditional characters and Taiwan terms (檔案, 設定).
  Brazilian Portuguese was largely European Portuguese (ficheiro, Partilhar,
  Definições); it now says arquivo, Compartilhar, Ajustes.
- **Settings is translated everywhere.** The Theme row with its Auto, Light
  and Dark options and the "This device · tap to rename" line were English
  in every language.
- **The tab bar no longer overflows in Spanish.** A label that needed two
  lines pushed the bar past its height; labels stay on one line and the Inbox
  tab has a shorter name in Spanish, French and Brazilian Portuguese.

### Changed
- **License: MIT → Apache License 2.0** (2026-10-07). Copies of earlier
  releases obtained under MIT keep those terms. Forks must keep the new
  `NOTICE` file, and the BIShare name, logo and app icon are not licensed for
  use by forks; see `TRADEMARKS.md`.

## [2.5.9] — 2026-10-03

### Fixed
- **Received files keep their original "Date modified".** Until now a file
  arrived stamped with the moment the transfer finished, so a document last
  edited in March showed today's date on the other device — a deal-breaker
  for anyone who sorts or syncs by date. The sender now includes the file's
  modification time with every transfer and the receiver writes it onto the
  saved file: over Wi-Fi (TCP and QUIC), offline Nearby on iPhone, iPad and
  Mac, a browser sending to the app, a web link opened in the app, and a
  cloud link. On Android the file picker hands the app a copy made at that
  instant, so the app now asks the original file for its date before sending.
  Transfers from an older version arrive as before. A browser on the
  receiving end cannot set a download's date — that is the browser, not
  BIShare; files inside a bundle ZIP do keep their dates.
- **Turning receiving off from the Mac menu bar no longer hangs.** Stopping
  the server waited on the QUIC listener to end, which only ends once the
  server is stopped; it is now stopped first.

## [2.5.7] — 2026-09-19

### Fixed
- **App Share now sends apps that can actually be installed.** Almost every app
  from Google Play is installed as a base APK plus config splits, and the base
  alone refuses to install (`INSTALL_FAILED_MISSING_SPLIT`). App Share sent only
  the base — on the test phone that meant 31 of 36 apps arrived unusable. A
  split app is now sent as one `.apks` file holding the base and every split,
  byte for byte. The receiver installs it with a split-APK installer such as
  SAI; the picker says so before you send. Apps installed as a single APK are
  sent as a plain `.apk`, as before. The size shown is now the size sent.

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
