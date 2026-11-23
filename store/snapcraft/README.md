# Snap Store listing assets

Everything the Snap Store needs that `snapcraft.yaml` cannot carry. Title,
summary, description, licence, links and the app icon travel with the snap and
are pushed by CI (`snapcraft upload-metadata`); the files here are the media and
have to be uploaded once, by hand, at
https://snapcraft.io/bishare/listing

| File | Where it goes |
|---|---|
| `banner-1920x640.png` | Featured banner (the store requires 3:1, not 16:9) |
| `banner-icon-512.png` | Banner icon beside it |
| `01-send.png` … `05-settings.png` | Screenshots, in that order (2.8.0 redesign, replaced 2026-11-23) |

Also set on that page, because neither can live in the snap:

- **Category** — Utilities (secondary: Productivity). Without one the snap is
  reachable by search only, never by browsing Ubuntu's App Center.
- **Contact / issues links** are already in `snapcraft.yaml`; leave the
  dashboard fields empty so the snap stays the single source.

## Where these came from

The screenshots are the Microsoft Store set (`store/screenshots/windows/`):
the same Flutter desktop UI, composed on a branded canvas without OS window
chrome, so they are honest on Linux. The device names in them are made up
(Maya's PC, Nadia, Leo, Studio); never ship a shot with a real device name.

The banner is a 3:1 band cut from the 2400x1350 promo. The store rejects
16:9 outright, so the crop is centred on the logo and text block rather than
squashing the original.

If the app UI changes, rebuild the Windows set with `compose.py` and copy it
here rather than patching pixels.
