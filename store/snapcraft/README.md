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
| `01-send-anything.png` … `05-yours-to-set-up.png` | Screenshots, in that order |

Also set on that page, because neither can live in the snap:

- **Category** — Utilities (secondary: Productivity). Without one the snap is
  reachable by search only, never by browsing Ubuntu's App Center.
- **Contact / issues links** are already in `snapcraft.yaml`; leave the
  dashboard fields empty so the snap stays the single source.

## Where these came from

The screenshots are the Microsoft Store set: the same Flutter desktop UI, shot
without OS window chrome, so they are honest on Linux. Two edits were needed
for this store:

- `05-yours-to-set-up.png` had a real device called "cakra's Mac mini" in it.
  A store page should not carry someone's device name, and a Mac is the wrong
  machine to show on a Linux listing, so the row now reads "Linux desktop".
- The banner is a 3:1 band cut from the 2400x1350 promo. The store rejects
  16:9 outright, so the crop is centred on the logo and text block rather than
  squashing the original.

If the app UI changes, reshoot from `store/screenshots/raw` rather than
patching pixels again.
