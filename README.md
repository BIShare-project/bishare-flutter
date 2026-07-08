# BIShare — Flutter Client (P0 Scaffold)

Satu codebase Dart/Flutter menggantikan native iOS + Android **dan** rencana Tauri desktop — target penuh **iOS, Android, macOS, Windows, Linux**. Rencana lengkap: [`../flutter-client.md`](../flutter-client.md).

## Status: P0 Foundation (compile-verified)

`flutter analyze` **bersih (0 issue)**, 5 test crypto **hijau**, `cargo build` FFI **sukses**.

### Sudah jadi & terverifikasi

| Area | File | Catatan |
|---|---|---|
| Konstanta protokol (grounded) | `lib/core/constants/protocol.dart` | Port 58317–58320, `_bishare._tcp`, path API, versi 2.3, crypto — **byte-exact** dari `bishare-protocol` |
| Wire DTO | `lib/core/protocol/*` | `DeviceInfo` (+ self-reported `ip`), `FileMetadata`, `Prepare*`, `UploadResponse` — cocok persis JSON native |
| **E2E crypto** | `lib/core/crypto/e2e_crypto.dart` | X25519 + HKDF-SHA256 (`BIShare-E2E`/`file-transfer`) + AES-256-GCM, chunk-nonce XOR — **interop byte-exact, teruji round-trip** |
| Identity | `lib/core/identity/device_identity.dart` | fingerprint UUID, alias, keypair (secure storage), `makeDeviceInfo()` refresh IP |
| Self-report IPv4 | `lib/core/network/local_ip.dart` | hindari loopback/link-local/AWDL-IPv6 — **fix discovery** |
| Discovery | `lib/features/discovery/data/discovery_service.dart` | `bonsoir` advertise+browse, TXT fast-path `ip`, stale sweep |
| Receiver | `lib/core/server/transfer_server.dart` | `shelf` dual-stack :58317 — info/prepare(accept·reject·PIN·busy·30s·**derive-key**)/upload(**stream-decrypt** `[len][nonce\|ct\|tag]` frames→disk + sha256 plaintext)/cancel/goodbye |
| Sender | `lib/features/send/data/transfer_client.dart` | `dio` — info/prepare/upload (**E2E chunked-encrypt stream**, `X-Encrypted: chunked`)/cancel/goodbye + **cancel-propagation** |
| **E2E transfer** | client+server + `bishare_ffi` | ECDH key negotiate lewat prepare `publicKey`, chunk `encrypt_chunk`/`decrypt_chunk` di **Rust FFI**, framing **byte-exact native** (baseNonce dari chunk-0), verifikasi sha256 plaintext — teruji round-trip + split-jaringan |
| DI + BLoC + UI | `lib/core/di`, `lib/features/*/presentation`, `lib/features/home` | get_it + flutter_bloc + Home yang runnable |
| **FFI (flutter_rust_bridge)** | `rust/` + `lib/src/rust/` + `lib/core/rust/rust_facade.dart` | **wired end-to-end**: crate `bishare_ffi` reuse `bishare-protocol` (crypto/utils), binding Dart ter-generate, `RustLib.init()` di bootstrap, receiver pakai `sanitizeFilename` Rust. `flutter build macos` membundel `bishare_ffi.framework` (11 MB, symbol FRB terverifikasi via `nm`) |

### Scope P0 yang menyusul (jujur, bukan bug — belum diimplementasi)

1. **QUIC** — TCP dulu (sesuai default nyata native); QUIC via `quinn` di `bishare_ffi` = P7.
2. **injectable/freezed/drift/retrofit codegen** — scaffold pakai get_it manual + json_serializable; migrasi ke anotasi = increment.
3. Dep `device_info_plus`/`network_info_plus`/`connectivity_plus` dilepas sementara (konflik `win32 6 vs 5.9` dengan file_picker) — re-add saat dipakai.
4. **Verifikasi interop di device nyata** — E2E teruji round-trip di Dart + build; transfer Flutter↔iOS/Android di jaringan asli belum dijalankan (butuh device).
5. **Offload decrypt ke isolate** — FFI sync per-chunk di isolate server saat file besar (perf, bukan correctness).

## Menjalankan

```bash
flutter pub get
dart run build_runner build   # generate *.g.dart (json_serializable)
flutter run -d macos          # atau ios / windows / linux / android
flutter analyze               # 0 issue
flutter test                  # crypto round-trip
```

Dua device di Wi-Fi yang sama akan saling terlihat; tap device → pilih file → prompt Accept di penerima → transfer + progress.

## Arsitektur

Clean Architecture feature-first (`core/` + `features/<f>/{domain,data,presentation}`), BLoC (Cubit) untuk state, get_it untuk DI, Dio (sender) + shelf (receiver), `flutter_rust_bridge` untuk reuse protokol Rust. Detail: `../flutter-client.md` §2–3.
