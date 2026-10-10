#!/usr/bin/env bash
# Publish a GitHub release's installers to the SourceForge project.
#
#   SOURCEFORGE_USER=<name> packaging/sourceforge.sh 2.6.1
#   DRY_RUN=1 packaging/sourceforge.sh 2.6.1      # download and list, upload nothing
#
# SourceForge got versions 2.4.5 to 2.5.1 once, when the project was created,
# and nothing after: on 2026-10-10 its default download was still 2.5.1 while
# 2.6.1 was in the stores. This copies a release there the way the tag already
# feeds Snap, Scoop and the Homebrew cask.
#
# What goes up, into /v<version>/: every BIShare-* file of the GitHub release
# except the .aab (a Play upload bundle, not something a person can install),
# plus the release notes as README.md, which SourceForge shows under the file
# list.
#
# Needs: gh (logged in, or GH_TOKEN), rsync, ssh, and an SSH key whose public
# half is in the SourceForge account (Account Settings, SSH Settings). The key
# is read from SOURCEFORGE_SSH_KEY_FILE, default ~/.ssh/bishare_sourceforge.
# With SOURCEFORGE_API_KEY (Account Settings, Releases API Key) it also makes
# the new files the default download for each OS; without it that stays a
# click in the project's Files page.
set -euo pipefail
VER="${1:?usage: sourceforge.sh <version>}"; VER="${VER#v}"
PROJECT="bishare-flutter"
REPO="BIShare-project/bishare-flutter"
HOST="frs.sourceforge.net"
# ED25519 host key of frs.sourceforge.net, as SourceForge publishes it:
# https://sourceforge.net/p/forge/documentation/SSH%20Key%20Fingerprints/
HOST_FINGERPRINT="SHA256:209BDmH3jsRyO9UeGPPgLWPSegKmYCBIya0nR/AWWCY"
KEY="${SOURCEFORGE_SSH_KEY_FILE:-$HOME/.ssh/bishare_sourceforge}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir "$TMP/out"
gh release download "v$VER" --repo "$REPO" --dir "$TMP/out" --pattern 'BIShare-*'
rm -f "$TMP/out"/*.aab
# README.md: this version's section of CHANGELOG.md when the file is at hand,
# otherwise the GitHub release text (which is often just a compare link).
CHANGELOG="$(dirname "$0")/../CHANGELOG.md"
if [ -r "$CHANGELOG" ] && grep -q "^## \\[$VER\\]" "$CHANGELOG"; then
  { echo "# BIShare $VER"; echo
    awk -v v="$VER" '$0 ~ "^## \\[" v "\\]" { on = 1; next } on && /^## \[/ { exit } on' "$CHANGELOG"
    echo; echo "https://bishare.app · https://github.com/$REPO"; } > "$TMP/out/README.md"
else
  gh release view "v$VER" --repo "$REPO" --json body --jq .body > "$TMP/out/README.md"
fi
echo "v$VER, to $HOST:/home/frs/project/$PROJECT/v$VER/"
( cd "$TMP/out" && ls -l | awk 'NR > 1 { printf "  %10d  %s\n", $5, $NF }' )

if [ -n "${DRY_RUN:-}" ]; then
  echo "dry run: nothing uploaded"; exit 0
fi
: "${SOURCEFORGE_USER:?set SOURCEFORGE_USER to the SourceForge account name}"
[ -r "$KEY" ] || { echo "no SSH key at $KEY (set SOURCEFORGE_SSH_KEY_FILE)" >&2; exit 1; }

# The host is trusted by its published fingerprint, not by whatever answers
# first: scan the key, compare, and let ssh accept that one key only.
ssh-keyscan -t ed25519 "$HOST" > "$TMP/known_hosts" 2>/dev/null
GOT="$(ssh-keygen -lf "$TMP/known_hosts" | awk '{ print $2 }')"
[ "$GOT" = "$HOST_FINGERPRINT" ] || {
  echo "host key of $HOST is '$GOT', expected $HOST_FINGERPRINT" >&2; exit 1; }

rsync -av \
  -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMP/known_hosts" \
  "$TMP/out/" "$SOURCEFORGE_USER@$HOST:/home/frs/project/$PROJECT/v$VER/"
echo "  uploaded"

if [ -z "${SOURCEFORGE_API_KEY:-}" ]; then
  echo "  SOURCEFORGE_API_KEY not set: choose the default download for each OS in the project's Files page"
  exit 0
fi
# https://sourceforge.net/p/forge/documentation/Using%20the%20Release%20API/
default_for() {  # <file> <platform>...
  local file="$1"; shift
  local args=(); for p in "$@"; do args+=(-d "default=$p"); done
  curl -fsS -o /dev/null -H "Accept: application/json" -X PUT "${args[@]}" -d "api_key=$SOURCEFORGE_API_KEY" \
    "https://sourceforge.net/projects/$PROJECT/files/v$VER/$file" && echo "  default for $*: $file"
}
default_for "BIShare-$VER-windows-x64.zip" windows
default_for "BIShare-$VER-macos.dmg" mac
default_for "BIShare-$VER-linux-x86_64.AppImage" linux
default_for "BIShare-$VER-android.apk" others
echo "done."
