#!/bin/sh
# Store screenshots for every app language and store device, no simulator:
#
#   store/screens/shoot.sh <out-dir> [lang ...]
#
# 1. test/preview/store_screenshots_test.dart renders the raw screens on the
#    host, one process per language (fonts differ per script);
# 2. frame.py adds the status bar, the device, the captions and the badges.
# Writes <out-dir>/_raw/<preset>/<lang>/*.png and <out-dir>/<lang>/<target>/*.png.
# Needs the fonts first: fetch_fonts.sh, then instance_fonts.py (fontTools).
set -e
cd "$(dirname "$0")/../.."
out=${1:?usage: store/screens/shoot.sh <out-dir> [lang ...]}
shift
langs=${*:-"en id ar de es fr hi ja ko pt-BR ru zh-Hans zh-Hant"}
for lang in $langs; do
  echo "== $lang"
  # a failure (an overflow, a missing key) still writes the images: report
  # it and go on, then look at that language before using its screenshots
  BISHARE_SHOTS_DIR="$out/_raw" BISHARE_SHOTS_LOCALES="$lang" \
    flutter test test/preview/store_screenshots_test.dart --reporter=failures-only \
    || echo "!! $lang: test reported errors, check its screenshots"
done
for lang in $langs; do
  python3 store/screens/frame.py --raw "$out/_raw" --out "$out" --lang "$lang"
done
