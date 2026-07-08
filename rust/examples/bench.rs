//! Pure-Rust crypto ceiling (no FFI/Dart). `cargo run --release --example bench`.
//! With `.cargo/config.toml` active this reflects whether hardware AES is on.
use bishare_protocol::crypto::Encryption;
use std::time::Instant;

fn main() {
    let key: [u8; 32] = std::array::from_fn(|i| i as u8);
    let nonce: [u8; 12] = std::array::from_fn(|i| i as u8);
    let plain = vec![0x42u8; 256 * 1024];
    let chunks = 512u64; // 128 MB
    let t = Instant::now();
    for i in 0..chunks {
        let enc = Encryption::encrypt_chunk(&plain, &key, i, &nonce).unwrap();
        let dec = Encryption::decrypt_chunk(&enc, &key, i, &nonce).unwrap();
        std::hint::black_box(&dec);
    }
    let secs = t.elapsed().as_secs_f64();
    let mb = (chunks as f64) * 256.0 * 1024.0 / (1024.0 * 1024.0);
    println!("PURE-RUST CRYPTO: {:.1} MB/s (encrypt+decrypt {mb} MB in {:.0} ms)",
        mb / secs, secs * 1000.0);
    // Is hardware AES compiled in?
    println!("cfg aes_armv8 = {}", cfg!(aes_armv8));
    println!("cfg polyval_armv8 = {}", cfg!(polyval_armv8));
}
