# Store screenshots

Localized screenshots for the App Store (iPhone, iPad, Mac) and Google Play
(phone, tablet), in all 13 app languages, built on the Mac without a
simulator or an emulator.

```sh
store/screens/fetch_fonts.sh                       # once: OFL fonts (git-ignored)
python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
/tmp/ft/bin/python store/screens/instance_fonts.py # once: static + merged fonts
store/screens/shoot.sh <out-dir> [lang ...]        # raw captures, then frames
```

`shoot.sh` writes `<out-dir>/<lang>/<target>/<n>_<screen>.png`:

| Target | Size | Store slot |
|---|---|---|
| `ios_phone` | 1290×2796 | App Store iPhone 6.9"/6.7" (`APP_IPHONE_67`) |
| `ios_ipad` | 2064×2752 | App Store iPad 13" (`APP_IPAD_PRO_3GEN_129`) |
| `mac` | 2880×1800 | Mac App Store (`APP_DESKTOP`) |
| `play_phone` | 1440×2560 | Google Play phone (9:16; Play refuses a side over 2× the other) |
| `play_tablet` | 1600×2560 | Google Play 7" and 10" tablet |

## How it works

1. `test/preview/store_screenshots_test.dart` renders the app's real screens
   (Share, Secure Link, QR Beam, a room, Settings) with fixed state: three
   peers, a room with three members and three files, default settings. It runs
   as a host widget test with `debugDefaultTargetPlatformOverride`, so the iOS,
   Android and macOS variants of the UI are the ones each store shows. One
   process per language: for Arabic, Hindi, Japanese, Korean and Chinese it
   loads IBM Plex Sans with the matching Noto glyphs merged in, the way a phone
   falls back to its system fonts.
2. `frame.py` paints the status bar and home indicator, puts the capture in a
   device, and adds the eyebrow, headline, sub line and two badges from
   `captions.py`.

Captions are written by hand per language (no machine translation). Facts in
them are checked against the app and the API; never put a transfer speed or a
time on a badge.

Nothing here uploads. Pushing screenshots to a store is a separate, approved
step.
