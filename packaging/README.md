# Packaging manifests

Manifests for the package managers that install BIShare from GitHub Releases.
Linux `.deb` / AppImage / tar.gz, the Windows ZIP and the notarized macOS DMG
are built by `.github/workflows/release.yml`; the Snap by `snap.yml`.

| Manager | Source | State |
|---|---|---|
| Scoop | `scoop/bishare.json` | works today, no submission needed |
| winget | `winget/*.yaml` (1.6.0, portable zip) | one-time PR to `microsoft/winget-pkgs` |
| Chocolatey | `chocolatey/` | one-time `choco push` |
| Homebrew | `homebrew/bishare.rb` (cask, DMG) | third-party tap now; `homebrew/cask` once notable |

**Every manifest is rewritten automatically on each tag** by the `packaging`
job in `release.yml`, which runs `packaging/bump.sh <version>`: it downloads
the release ZIP and DMG, computes their SHA-256, updates all five files and
commits them to `main`. Run it by hand for the same result:

```bash
packaging/bump.sh 2.4.7          # rewrite manifests
packaging/bump.sh 2.4.7 --tap    # …and push the cask to BIShare-project/homebrew-tap
```

The asset names are load-bearing — `BIShare-<ver>-windows-x64.zip` and
`BIShare-<ver>-macos.dmg` — Scoop `autoupdate`, the winget update flow, the
cask URL and `bump.sh` all derive URLs from them. Don't rename artifacts.

## Scoop

```powershell
scoop install https://raw.githubusercontent.com/BIShare-project/bishare-flutter/main/packaging/scoop/bishare.json
```

`checkver`/`autoupdate` track new releases. For a proper bucket, copy the file
into a `BIShare-project/scoop-bucket` repo or submit to Scoop `extras`.

## winget

First submission (once):

1. `winget validate --manifest packaging/winget` on a Windows machine.
2. Fork `microsoft/winget-pkgs`, copy the three files to
   `manifests/b/BIShareProject/BIShare/<version>/`, open a PR. Automated
   validation takes hours; a human review follows.

Later versions: `wingetcreate update BIShareProject.BIShare -u <zip-url> -s -t <token>`,
or PR the refreshed files. After the first merge: `winget install bishare`.

## Chocolatey

First submission (once), on a Windows machine with Chocolatey:

```powershell
cd packaging/chocolatey
choco pack                                  # → bishare.<version>.nupkg
choco install bishare -s . -y               # local install test
choco apikey --key <your-key> --source https://push.chocolatey.org/
choco push bishare.<version>.nupkg --source https://push.chocolatey.org/
```

Moderation (automated + human) usually takes a few days. The package installs
the portable ZIP, shims `bishare.exe` as a GUI app and adds a Start Menu
shortcut. After approval: `choco install bishare`.

## Homebrew

The cask needs a **released** `BIShare-<ver>-macos.dmg` (Developer ID signed and
notarized — the `macos` job produces it on every tag). Two routes:

- **Third-party tap — works immediately.** `bump.sh <ver> --tap` creates or
  updates `BIShare-project/homebrew-tap`. Users:
  `brew install BIShare-project/tap/bishare`
- **`homebrew/cask` — later.** Homebrew judges notability (roughly: a real
  user base, independent interest; GitHub stars/forks are the usual proxy).
  Submit a PR once the repo is past that bar; until then the tap is the
  supported path. Before the PR: `brew audit --cask --new bishare` and
  `brew style --fix` from within the tap.
