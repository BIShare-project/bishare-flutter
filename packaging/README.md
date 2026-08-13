# Packaging manifests

Manifests for package managers that install BIShare from the Windows ZIP on
GitHub Releases. Linux `.deb` / AppImage / tar.gz are built by
`.github/workflows/release.yml`; the Snap by `snap.yml`.

## Scoop (works today, no submission needed)

```powershell
scoop install https://raw.githubusercontent.com/BIShare-project/bishare-flutter/main/packaging/scoop/bishare.json
```

The manifest carries `checkver`/`autoupdate`, so a bucket (or `scoop update`)
tracks new GitHub releases automatically. To ship it in a proper bucket later,
copy `scoop/bishare.json` into a `bishare-project/scoop-bucket` repo (or
submit to scoop's `extras`).

## winget (needs a one-time PR to microsoft/winget-pkgs)

The three files in `winget/` are a complete 1.6.0 manifest for the current
release. To submit a version:

1. Update `PackageVersion`, `InstallerUrl`, and `InstallerSha256`
   (`sha256sum BIShare-<ver>-windows-x64.zip`, uppercase) in all three files.
2. Validate locally: `winget validate --manifest packaging/winget`.
3. PR them to `microsoft/winget-pkgs` under
   `manifests/b/BIShareProject/BIShare/<version>/`
   (or run `wingetcreate update BIShareProject.BIShare -u <zip-url> -s -t <token>`
   after the first manual submission is merged).

After the first merge, users install with `winget install bishare`.

## Release checklist additions

When tagging a release: the ZIP name pattern
`BIShare-<ver>-windows-x64.zip` is load-bearing — Scoop `autoupdate` and the
winget update flow both derive URLs from it. Don't rename artifacts.
