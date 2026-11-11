#!/bin/zsh
# Store screenshots taken by the iOS Simulator itself (simctl io screenshot):
# the device's own status bar, side strip and screen, with the sample content
# of test/preview/store_screenshots_test.dart (loaded by the test, not the app).
#
#   store/screens/shoot_sim.sh <simulator-id> <preset> <display> <out-dir> [lang,lang]
#
#   preset   ios_duo_outer (iPhone Duo closed, display 1)
#            ios_duo_inner (iPhone Duo open, display 3)
#   display  the simctl screen id (`xcrun simctl io <id> enumerate`)
#
# Put the simulator in the preset's pose first. Writes <out-dir>/<preset>/
# <lang>/<n>_<screen>.png; then frame with
#   frame.py --raw <out-dir> --out <dir> --lang <lang> --sim
set -e
cd "$(dirname "$0")/../.."
sim=${1:?simulator id}
preset=${2:?preset}
display=${3:?display}
out=${4:?out dir}
langs=${5:-}
defines=(
  --dart-define=BISHARE_SHOTS_DEVICE=true
  --dart-define=BISHARE_SHOTS_ROOT=$PWD
  --dart-define=BISHARE_SHOTS_DIR=$out/_flutter
  --dart-define=BISHARE_SHOTS_PRESETS=$preset
  --dart-define=BISHARE_SHOTS_ONLY=share,link,drive,inbox,settings
)
[[ -n $langs ]] && defines+=(--dart-define=BISHARE_SHOTS_LOCALES=$langs)
flutter test integration_test/store_shots_test.dart -d "$sim" "${defines[@]}" 2>&1 |
  while IFS= read -r line; do
    print -r -- "$line"
    if [[ $line == *BISHARE_SHOT\ * ]]; then
      rel=${line##*BISHARE_SHOT }
      # the drive/ review screens are not store shots
      [[ $rel == */drive/* ]] && continue
      target="$out/$rel.png"
      mkdir -p "${target:h}"
      sleep 1.2
      xcrun simctl io "$sim" screenshot --display="$display" "$target" >/dev/null
      print -r -- "saved $target"
    fi
  done
