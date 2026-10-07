#!/bin/sh
# Caption faces for frame.py, all SIL Open Font License, from the Google Fonts
# repository. They are large (the CJK ones ~10 MB each), so they are fetched
# into store/screens/fonts/ (git-ignored) instead of being committed.
set -e
cd "$(dirname "$0")"
mkdir -p fonts
base=https://github.com/google/fonts/raw/main/ofl
for f in \
  "plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf PlusJakartaSans.ttf" \
  "manrope/Manrope%5Bwght%5D.ttf Manrope.ttf" \
  "notosansarabic/NotoSansArabic%5Bwdth,wght%5D.ttf NotoSansArabic.ttf" \
  "notosansdevanagari/NotoSansDevanagari%5Bwdth,wght%5D.ttf NotoSansDevanagari.ttf" \
  "notosansjp/NotoSansJP%5Bwght%5D.ttf NotoSansJP.ttf" \
  "notosanskr/NotoSansKR%5Bwght%5D.ttf NotoSansKR.ttf" \
  "notosanssc/NotoSansSC%5Bwght%5D.ttf NotoSansSC.ttf" \
  "notosanstc/NotoSansTC%5Bwght%5D.ttf NotoSansTC.ttf"; do
  set -- $f
  [ -s "fonts/$2" ] || curl -fsSL "$base/$1" -o "fonts/$2"
  echo "fonts/$2 $(wc -c < "fonts/$2" | tr -d ' ') bytes"
done
