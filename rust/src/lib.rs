//! `bishare_ffi` — the Flutter client's Rust bridge.
//!
//! Everything under [`api`] is a thin, owned-argument wrapper over the shared
//! `bishare-protocol` crate, exposed to Dart by flutter_rust_bridge. The wire /
//! crypto logic is therefore identical to the iOS/Android/desktop apps.

mod api;
mod engine;
mod frb_generated;
