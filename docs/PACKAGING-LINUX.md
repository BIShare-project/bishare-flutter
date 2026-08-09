# Packaging BIShare for Linux (Snap)

BIShare ships to Linux as a [Snap](https://snapcraft.io/). The recipe lives in
[`snap/snapcraft.yaml`](../snap/snapcraft.yaml); the desktop entry and icon are
in [`snap/gui/`](../snap/gui/).

> **Snaps build on Linux.** You cannot build a snap on macOS or Windows
> directly. Use a Linux machine (or VM), or let CI build it — see below.

## What's in the recipe

- **`core22`** base, **strict** confinement, **stable** grade.
- The **`gnome` extension** supplies the GTK3 runtime, themes, fonts, and
  desktop-portal plumbing a Flutter Linux app needs.
- A **`rust-toolchain`** part installs Rust via rustup so cargokit can build the
  `bishare_ffi` core during `flutter build linux`. The `bishare-protocol` crate
  is **vendored** (`rust/bishare-protocol`), so the build needs no access to any
  private repo.
- **Version** is derived automatically from `pubspec.yaml`.

### Interfaces (plugs)

| Plug | Why |
|------|-----|
| `network`, `network-bind` | LAN transfer + the local `shelf` receiver + cloud relay |
| `avahi-observe` | mDNS discovery via the host avahi daemon (`bonsoir`) |
| `camera` | QR scanning / QR Beam receive (`mobile_scanner`) |
| `home`, `removable-media` | open/save the files the user picks |
| `audio-playback` | notification / transfer sounds |

## Build locally

Install the tooling (one time):

```bash
sudo snap install snapcraft --classic
sudo snap install lxd        # build backend
sudo lxd init --auto
```

Then, from the repo root:

```bash
snapcraft            # builds ./bishare_<version>_amd64.snap
```

Install and test the local build:

```bash
sudo snap install ./bishare_*_amd64.snap --dangerous
bishare              # launch

# Some interfaces don't auto-connect for a locally-installed (--dangerous) snap.
# Connect them manually to test discovery + camera:
sudo snap connect bishare:camera
sudo snap connect bishare:avahi-observe
```

To iterate faster, `snapcraft --debug` drops you into the build VM on failure,
and `snapcraft clean bishare` rebuilds just the app part.

## Publish to the Snap Store

```bash
snapcraft login
snapcraft register bishare          # one time — claims the name
snapcraft upload ./bishare_*_amd64.snap --release=stable
```

Camera, network, and removable-media auto-connect on Store installs; other
interfaces may need a manual `snap connect` or a store-granted assertion.

## CI

[`.github/workflows/snap.yml`](../.github/workflows/snap.yml) builds the snap on
every tag using `snapcore/action-build`, and uploads it as a workflow artifact.
Wire in `snapcore/action-publish` with a `SNAPCRAFT_STORE_CREDENTIALS` secret
(from `snapcraft export-login`) when you're ready to auto-publish to a channel.

## Known caveats (please help test)

- **mDNS registration under strict confinement.** `avahi-observe` lets BIShare
  *browse/resolve* peers via the host avahi daemon. *Publishing* its own service
  can be restricted; if a device isn't discoverable, BIShare falls back to its
  subnet probe, so transfers still work — but this needs verification on real
  distros. Reports welcome.
- **`flutter` plugin on `core22`.** If the `flutter` plugin fails to fetch the
  SDK on your snapcraft version, replace the `bishare` part with a manual SDK
  part (clone `flutter` at a pinned tag, then run `flutter build linux
  --release` in `override-build`). Track this in an issue if you hit it.
- **First build is slow** — it compiles the Rust core *and* the Flutter engine
  from scratch. Subsequent builds reuse the LXD cache.

Have a fix or a working tweak? PRs to the recipe are very welcome — Linux
packaging is exactly the kind of thing the community is great at.
