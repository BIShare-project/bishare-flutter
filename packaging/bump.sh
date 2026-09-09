#!/usr/bin/env bash
# Update every package-manager manifest to a published GitHub release.
#
#   packaging/bump.sh 2.4.7          # rewrite manifests in-repo
#   packaging/bump.sh 2.4.7 --tap    # …and push the cask to BIShare-project/homebrew-tap
#
# Reads the release assets from GitHub, computes their SHA-256, and rewrites
# winget (3 files), Scoop, Chocolatey and the Homebrew cask. Nothing is
# submitted anywhere; see packaging/README.md for the submission steps.
set -euo pipefail
VER="${1:?usage: bump.sh <version> [--tap]}"; VER="${VER#v}"
TAP="${2:-}"
REPO="BIShare-project/bishare-flutter"
BASE="https://github.com/$REPO/releases/download/v$VER"
ZIP="BIShare-$VER-windows-x64.zip"; DMG="BIShare-$VER-macos.dmg"
cd "$(dirname "$0")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fetch() { curl -fsSL --retry 3 -o "$TMP/$1" "$BASE/$1" || { echo "missing release asset: $BASE/$1" >&2; exit 1; }; }

fetch "$ZIP"; ZIP_SHA="$(sha "$TMP/$ZIP")"
fetch "$DMG"; DMG_SHA="$(sha "$TMP/$DMG")"
echo "v$VER  zip $ZIP_SHA"
echo "v$VER  dmg $DMG_SHA"

python3 - "$VER" "$ZIP_SHA" "$DMG_SHA" <<'PY'
import re, sys, pathlib
ver, zip_sha, dmg_sha = sys.argv[1:4]
zip_url = f"https://github.com/BIShare-project/bishare-flutter/releases/download/v{ver}/BIShare-{ver}-windows-x64.zip"
def edit(path, subs):
    p = pathlib.Path(path); s = p.read_text()
    for pat, rep in subs:
        s, n = re.subn(pat, rep, s, flags=re.M)
        assert n >= 1, f"{path}: pattern not found: {pat}"
    p.write_text(s); print("  updated", path)
for f in ("winget/BIShareProject.BIShare.yaml", "winget/BIShareProject.BIShare.locale.en-US.yaml"):
    edit(f, [(r"^PackageVersion: .*$", f"PackageVersion: {ver}")])
edit("winget/BIShareProject.BIShare.installer.yaml", [
    (r"^PackageVersion: .*$", f"PackageVersion: {ver}"),
    (r"^(\s*InstallerUrl: ).*$", rf"\g<1>{zip_url}"),
    (r"^(\s*InstallerSha256: ).*$", rf"\g<1>{zip_sha.upper()}"),
])
edit("scoop/bishare.json", [
    (r'"version": "[^"]+"', f'"version": "{ver}"'),
    (r'"url": "https://github\.com/[^"]+windows-x64\.zip"', f'"url": "{zip_url}"'),
    (r'"hash": "[0-9a-f]+"', f'"hash": "{zip_sha}"'),
])
edit("chocolatey/bishare.nuspec", [(r"<version>[^<]+</version>", f"<version>{ver}</version>")])
edit("chocolatey/tools/chocolateyinstall.ps1", [
    (r"url64bit\s*= '[^']+'", f"url64bit       = '{zip_url}'"),
    (r"checksum64\s*= '[0-9a-f]+'", f"checksum64     = '{zip_sha}'"),
])
edit("homebrew/bishare.rb", [
    (r'^  version "[^"]+"', f'  version "{ver}"'),
    (r'^  sha256 "[0-9a-f]+"', f'  sha256 "{dmg_sha}"'),
])
PY

if [ "$TAP" = "--tap" ]; then
  # A third-party tap works today without Homebrew's notability bar:
  #   brew install BIShare-project/tap/bishare
  TAPREPO="BIShare-project/homebrew-tap"
  gh repo view "$TAPREPO" >/dev/null 2>&1 || gh repo create "$TAPREPO" --public \
    --description "Homebrew tap for BIShare — brew install BIShare-project/tap/bishare"
  git clone -q "https://github.com/$TAPREPO.git" "$TMP/tap"
  mkdir -p "$TMP/tap/Casks"; cp homebrew/bishare.rb "$TMP/tap/Casks/bishare.rb"
  [ -f "$TMP/tap/README.md" ] || printf '# BIShare Homebrew tap\n\n```\nbrew install BIShare-project/tap/bishare\n```\n' > "$TMP/tap/README.md"
  ( cd "$TMP/tap" && git add -A && git -c user.name=bishare-release -c user.email=support@billiongroup.net \
      commit -q -m "bishare $VER" && git push -q origin HEAD ) && echo "  pushed cask to $TAPREPO"
fi
echo "done. Next: see packaging/README.md (winget PR, choco push)."
