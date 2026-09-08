# Store screenshots

`windows/` holds the 1920×1080 PNGs for the Microsoft Store listing, plus the
2160×2160 product logo and a 16:9 promotional image. `raw/` holds the
untouched app captures they are built from; `compose.py` rebuilds the composed
set from `raw/`.

| File | Caption |
|---|---|
| `01-secure-link.png` | Send anything, to anyone |
| `02-encryption.png` | Encrypted before it leaves your PC |
| `03-rooms.png` | Rooms: one code, several devices |
| `04-devices.png` | Windows, iPhone, Android, Mac and Linux |
| `05-settings.png` | Yours to set up |
| `store-logo-2160.png` | Product logo, transparent background, from `logo.svg` |
| `promo-16x9-2400x1350.png` | Promotional image |

## Why the app is composed onto a background

The window is locked to 1000×680 and is not resizable (`desktop_service.dart`),
so a raw capture can never reach the Store's 1366×768 minimum. Each shot is the
real app UI, unretouched, placed on a branded canvas. Only empty background
below the last row of content is trimmed — nothing inside the UI is cropped.

## Read this before submitting

**These were captured on macOS, not Windows.** The Flutter UI is the same
widget tree on both, and the macOS window chrome is excluded, so what you see
is what Windows draws — but it is not literally the Windows build. Recapture
them on the Windows machine you sideload the test MSIX onto (that step is
required anyway) if you want the listing to be captures of the shipped binary.

`01-secure-link.png` shows a real transfer code from a live upload. It was
one-time and expired 24h after 2026-09-08.
