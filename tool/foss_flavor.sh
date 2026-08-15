#!/bin/sh
# Prepares the working tree for the FOSS (F-Droid) build:
#   1. Points mobile_scanner at the pure-Dart stub in fdroid/mobile_scanner_stub
#      via dependency_overrides — Google's proprietary MLKit never enters the
#      build graph.
#   2. Refreshes the lockfile.
#
# The F-Droid recipe runs this in prebuild, then builds with:
#   flutter build apk --release --dart-define=BISHARE_FOSS=true
#
# Local test drive (repo stays dirty — `git checkout pubspec.yaml pubspec.lock`
# to undo):
#   sh tool/foss_flavor.sh && flutter build apk --release --dart-define=BISHARE_FOSS=true
set -eu
cd "$(dirname "$0")/.."

if grep -q "fdroid/mobile_scanner_stub" pubspec.yaml; then
  echo "foss_flavor: override already present"
else
  cat >> pubspec.yaml <<'EOF'

# --- FOSS build override (appended by tool/foss_flavor.sh) ---
dependency_overrides:
  mobile_scanner:
    path: fdroid/mobile_scanner_stub
EOF
  echo "foss_flavor: mobile_scanner overridden with stub"
fi

flutter pub get
echo "foss_flavor: ready — build with --dart-define=BISHARE_FOSS=true"
