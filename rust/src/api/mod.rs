pub mod crypto;
pub mod manifest;
pub mod quic;
pub mod scanner;
pub mod signal;
pub mod utils;

/// Runs once when the Rust library is initialised from Dart (`RustLib.init()`).
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
