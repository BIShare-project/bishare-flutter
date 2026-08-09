# Contributing to BIShare

Thanks for your interest in improving BIShare! This is a cross-platform file
sharing app built with **Flutter** (Dart) and a **Rust** core. Contributions of
all kinds are welcome — bug fixes, features, translations, docs, and design.

## Ways to help

- 🐛 **Report bugs** — open an issue with steps to reproduce and your platform.
- 💡 **Suggest features** — open an issue describing the problem you want solved.
- 🌍 **Translations** — add a new language or improve an existing one. It's the
  easiest way to contribute (just a text editor) — see **[docs/TRANSLATIONS.md](docs/TRANSLATIONS.md)**.
- 🧑‍💻 **Code** — pick up an issue labeled [`good first issue`](https://github.com/BIShare-project/bishare-flutter/labels/good%20first%20issue)
  or [`help wanted`](https://github.com/BIShare-project/bishare-flutter/labels/help%20wanted).

> For anything larger than a small fix, please open an issue first so we can
> align on direction before you invest time.

## Development setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ≥ 3.11).
- [Rust toolchain](https://rustup.rs/) (`rustc` + `cargo`) — the native crypto
  core builds from source.
- Platform toolchains for what you target (Xcode, Android Studio/NDK, Visual
  Studio, or GTK/Clang).

### Build & run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d macos      # or: ios | android | windows | linux
```

The Rust core (including the vendored `rust/bishare-protocol` crate) compiles on
the first build, so it takes a little longer up front.

## Before you open a PR

1. **Branch** off `main`: `git checkout -b feat/short-description`.
2. **Analyze & test** — both must pass:
   ```bash
   flutter analyze
   flutter test
   ```
3. **Localize everything** — any new user-facing string must have a key in **all**
   files under `assets/translations/`. Reference strings with `'my.key'.tr()`;
   never hard-code UI text. Verify parity with `dart run tool/check_translations.dart`.
4. **Match the code style** — feature-first structure under `lib/features/`,
   `flutter_bloc` (Cubit) for state, `shadcn_ui` widgets from `lib/core/ui/`.
5. **Keep commits focused** and write a clear PR description of what changed and
   why. Fill in the PR checklist.

## Project layout

See the **Project structure** section in the [README](README.md#project-structure).
In short: cross-cutting services live in `lib/core/`, features are vertical
slices in `lib/features/`, and the native crate is in `rust/`.

## Code of conduct

Be kind and constructive. We want BIShare to be a welcoming project. Harassment
or disrespectful behavior isn't tolerated.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
