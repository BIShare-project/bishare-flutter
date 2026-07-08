//! Prints golden crypto vectors from the shared `bishare-protocol` crate, used to
//! assert the Dart↔Rust FFI bridge is byte-identical (integration_test).
//! Run: `cargo run --example golden`
use bishare_protocol::crypto::Encryption;

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}

fn main() {
    let key: [u8; 32] = std::array::from_fn(|i| i as u8);
    let nonce: [u8; 12] = std::array::from_fn(|i| i as u8);
    let pt = b"BIShare cross-platform test vector";
    println!("chunk0={}", hex(&Encryption::encrypt_chunk(pt, &key, 0, &nonce).unwrap()));
    println!("chunk1={}", hex(&Encryption::encrypt_chunk(pt, &key, 1, &nonce).unwrap()));
    let a = Encryption::from_private_key(&[0x11u8; 32]);
    let b = Encryption::from_private_key(&[0x22u8; 32]);
    println!("apub={}", a.public_key_base64());
    println!("bpub={}", b.public_key_base64());
    println!("shared={}", hex(&a.derive_shared_key(&b.public_key_base64()).unwrap()));
    println!("afp={}", a.fingerprint());
}
