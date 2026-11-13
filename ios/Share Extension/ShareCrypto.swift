import Foundation
import CryptoKit
import Security

// End-to-end encryption for the share extension, a CryptoKit port of the
// scheme the app uses (lib/core/crypto/e2e_crypto.dart, the Rust engine):
//
//   key agreement  X25519, raw 32-byte public keys in base64
//   key            HKDF-SHA256(salt "BIShare-E2E", info "file-transfer"), 32 bytes
//   cipher         AES-256-GCM, combined nonce(12) | ciphertext | tag(16)
//   streaming      1 MiB chunks; chunk i's nonce is a random per-file base
//                  nonce XOR'd with big-endian i in its last 8 bytes
//   wire           every chunk framed as uint32 BE length | combined box,
//                  sent with the header `X-Encrypted: chunked`
//
// The receiver (TransferServer) derives the same key from the public key in
// the prepare request and answers with its own, so nothing new is needed on
// the receiving side.

/// The extension's own device identity, kept in its Keychain.
///
/// The app and the extension share no App Group, so the extension cannot read
/// the app's key. It keeps a stable identity of its own instead: one
/// fingerprint and one X25519 key, created on first use. The receiver sees the
/// same device every time, so key pinning and per-device auto-accept apply.
struct ShareIdentity {
    let fingerprint: String
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    private static let service = "app.bishare.share-extension"
    private static let fingerprintAccount = "fingerprint"
    private static let keyAccount = "x25519"

    /// The stored identity, created and stored on first use. Falls back to a
    /// fresh, unsaved one if the Keychain refuses, so a share never fails here.
    static func load() -> ShareIdentity {
        let fingerprint: String
        if let stored = read(fingerprintAccount).flatMap({ String(data: $0, encoding: .utf8) }),
           !stored.isEmpty {
            fingerprint = stored
        } else {
            fingerprint = UUID().uuidString.lowercased()
            write(fingerprintAccount, Data(fingerprint.utf8))
        }

        let key: Curve25519.KeyAgreement.PrivateKey
        if let raw = read(keyAccount),
           let stored = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            key = stored
        } else {
            key = Curve25519.KeyAgreement.PrivateKey()
            write(keyAccount, key.rawRepresentation)
        }
        return ShareIdentity(fingerprint: fingerprint, privateKey: key)
    }

    /// The AES-256 key shared with a receiver that sent [peerPublicKeyBase64],
    /// or nil when the key is malformed (the transfer then stays plaintext,
    /// exactly as with an older receiver that sends no key).
    func sessionKey(peerPublicKeyBase64: String) -> SymmetricKey? {
        guard var raw = Data(base64Encoded: peerPublicKeyBase64) else { return nil }
        // Legacy 44-byte X.509 SubjectPublicKeyInfo keys (old Android builds):
        // the raw key is the trailing 32 bytes after a fixed 12-byte header.
        if raw.count == 44, raw.prefix(12) == ShareIdentity.x509X25519Prefix {
            raw = raw.suffix(32)
        }
        guard raw.count == 32,
              let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw),
              let secret = try? privateKey.sharedSecretFromKeyAgreement(with: peer)
        else { return nil }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("BIShare-E2E".utf8),
            sharedInfo: Data("file-transfer".utf8),
            outputByteCount: 32
        )
    }

    private static let x509X25519Prefix = Data([
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00,
    ])

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func write(_ account: String, _ data: Data) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Seals one file's chunks for the wire. A new sealer (a new random base
/// nonce) is made for every upload attempt: reusing a nonce under one key
/// would break AES-GCM.
struct ChunkSealer {
    static let chunkSize = 1 << 20 // BIShareConfig.defaultChunkSize
    /// Per chunk on the wire: the 4-byte length plus nonce(12) and tag(16).
    static let overheadPerChunk = 4 + 12 + 16

    let key: SymmetricKey
    private let baseNonce: [UInt8]

    init(key: SymmetricKey) {
        self.key = key
        var n = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, n.count, &n)
        baseNonce = n
    }

    /// Bytes on the wire for a plaintext of [size] bytes.
    static func wireLength(plainSize size: Int) -> Int {
        let chunks = size == 0 ? 0 : (size + chunkSize - 1) / chunkSize
        return size + chunks * overheadPerChunk
    }

    /// Chunk [index] of the file, sealed and framed.
    func frame(_ plain: Data, index: UInt64) throws -> Data {
        var nonce = baseNonce
        for i in 0..<8 {
            nonce[4 + i] ^= UInt8(truncatingIfNeeded: index >> UInt64(8 * (7 - i)))
        }
        let box = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(data: nonce))
        guard let combined = box.combined else { throw CocoaError(.coderInvalidValue) }
        let len = UInt32(combined.count)
        var out = Data(capacity: 4 + combined.count)
        out.append(contentsOf: [
            UInt8(truncatingIfNeeded: len >> 24), UInt8(truncatingIfNeeded: len >> 16),
            UInt8(truncatingIfNeeded: len >> 8), UInt8(truncatingIfNeeded: len),
        ])
        out.append(combined)
        return out
    }
}
