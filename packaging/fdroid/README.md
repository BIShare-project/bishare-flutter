# F-Droid submission

F-Droid tidak menerima upload APK. Build server mereka meng-compile app ini
sendiri dari repo git publik, mengikuti resep `com.bishare.app.yml` yang harus
masuk ke repo **fdroiddata** milik F-Droid (di GitLab). Setelah resep merge,
setiap tag `v*` baru dibangun & dipublikasikan otomatis — tanpa tindakan apa pun.

## Prasyarat di repo ini (status)

- [x] Build variant FOSS: `tool/foss_flavor.sh` menukar `mobile_scanner`
      (bundel MLKit proprietary) dengan stub murni-Dart di
      `fdroid/mobile_scanner_stub/`; `--dart-define=BISHARE_FOSS=true`
      mematikan scan kamera (guard `supportsCameraScan`) dan menjadikan
      telemetri opt-in.
- [x] `google_sign_in` (proprietary Play Services, tak terpakai) dihapus.
- [x] Metadata fastlane (`fastlane/metadata/android/…`) — judul, deskripsi
      (en-US + id-ID), ikon, screenshot; F-Droid menarik listing dari sini.
- [x] Draft resep: `packaging/fdroid/com.bishare.app.yml`.
- [ ] **Tag `v2.4.6`** — tag pertama yang MEMUAT semua di atas. Resep menunjuk
      commit `v2.4.6`; MR baru bisa dibuka setelah tag ini ada.

## Uji lokal (tanpa tooling F-Droid)

```sh
sh tool/foss_flavor.sh
flutter build apk --release --dart-define=BISHARE_FOSS=true
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -iE "mlkit|barhopper"   # harus KOSONG
git checkout -- pubspec.yaml pubspec.lock   # bersihkan override
```

## Cara submit (butuh akun GitLab, gratis)

1. Buat akun di gitlab.com (kalau belum), lalu **fork**
   <https://gitlab.com/fdroid/fdroiddata>.
2. Di fork: tambah file `metadata/com.bishare.app.yml` = salinan
   `packaging/fdroid/com.bishare.app.yml` (satu file saja, tidak ada yang lain).
3. Buka **Merge Request** ke fdroiddata. Pipeline CI mereka otomatis me-lint
   resep dan mencoba MEMBANGUN app — kalau merah, perbaiki resep di MR yang
   sama sampai hijau.
4. Reviewer (relawan) memeriksa; balas komentar mereka di MR. Antrean review
   realistisnya **beberapa minggu**.
5. Setelah merge: siklus build+publish F-Droid (beberapa hari) → app tampil di
   f-droid.org. APK ditandatangani dengan **kunci F-Droid**, bukan kunci kita
   (jalur reproducible-signature ada, tapi lewati dulu untuk submission awal).

Jalur alternatif tanpa menulis MR sendiri: buka issue di
<https://gitlab.com/fdroid/rfp> ("Request For Packaging") berisi link repo —
relawan yang mengemas; antreannya lebih lambat.

## Update selanjutnya

`AutoUpdateMode: Version` + `UpdateCheckMode: Tags` di resep = bot F-Droid
memantau tag `v*`; setiap rilis baru dibangun otomatis. Yang perlu dijaga:
`tool/foss_flavor.sh` tetap berfungsi dan versionCode di pubspec naik.

## Anti-feature yang dideklarasikan

`NonFreeNet` — fitur internet opsional (tautan share, room jarak jauh,
telemetri opt-in) memakai relay bishare.app. Semua fitur LAN jalan tanpanya.
Ini label informatif yang lazim, bukan penolakan.
