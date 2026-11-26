# Store screenshots

`app/` (not in git, 1.2 GB, listed in `.git/info/exclude`) holds the 2.8.0 set
for the App Store and Play: `app/<lang>/<target>/` for ios_phone (6.9"),
ios_phone_61 (6.1", required), ios_ipad, ios_duo_outer, ios_duo_inner (upload by
hand), mac, play_phone, play_tablet, and `app/<lang>/creative/` for the App
Store search results image (3:2) and product page header (21:9). Rebuild:
`store/screens/shoot.sh`, `frame.py --raw app/_raw --out app`, `creative.py`.


`windows/` holds the 1920×1080 PNGs for the Microsoft Store listing, plus the
2160×2160 product logo and a 16:9 promotional image. `raw/` holds the
untouched app captures they are built from; `compose.py` rebuilds the composed
set from `raw/`.

| File | Caption |
|---|---|
| `01-send.png` | Send anything. To any device. |
| `02-inbox.png` | Every photo in original quality |
| `03-secure-link.png` | Send to anyone with a link |
| `04-drive.png` | BIShare Drive: only you hold the key |
| `05-settings.png` | End-to-end encrypted |
| `store-logo-2160.png` | Product logo, transparent background, from `logo.svg` |
| `promo-16x9-2400x1350.png` | Promotional image |

The raw `W*.png` come from `test/preview/store_screenshots_test.dart`, preset
`windows_store`, with
`BISHARE_SHOTS_ONLY=1_share,2_inbox,3_link,4_drive,5_settings` (2.8.0
redesign). Sample photos: `store/screens/photos` (Unsplash License).

## Why the app is composed onto a background

The window is locked to 1000×680 and is not resizable (`desktop_service.dart`),
so a raw capture can never reach the Store's 1366×768 minimum. Each shot is the
real app UI, unretouched, placed on a branded canvas. Only empty background
below the last row of content is trimmed — nothing inside the UI is cropped.

## Read this before submitting

**These were captured on macOS, not Windows.** The Flutter UI is the same
widget tree on both, and the macOS window chrome is excluded, so what you see
is what Windows draws — but it is not literally the Windows build. Recapture
them on the Windows machine you sideload the test MSIX onto (that step is
required anyway) if you want the listing to be captures of the shipped binary.

`01-secure-link.png` shows a real transfer code from a live upload. It was
one-time and expired 24h after 2026-09-08.

## Every language (`windows/<lang>/`)

`compose_l10n.py` builds the same five Microsoft Store shots for all 13 app
languages, with the captions of `store/screens/captions.py` and the caption
faces of `store/screens/frame.py` (Arabic, Hindi and CJK need them). Raw
captures first, one process per language:

    BISHARE_SHOTS_DIR=<raw> BISHARE_SHOTS_LOCALES=<lang> \
      BISHARE_SHOTS_PRESETS=windows_store \
      BISHARE_SHOTS_ONLY=1_share,2_inbox,3_link,4_drive,5_settings \
      flutter test test/preview/store_screenshots_test.dart
    python3 store/screenshots/compose_l10n.py <raw> [lang ...]

Needs Pillow with raqm. The listing text and the import CSV for Partner Center
come from `store/msstore_listing.py`; see its docstring for the import rules
that cost hours (folder name in image paths, no URLs in descriptions, and
small batches, since one 23 MB import trips Partner Center's firewall).
