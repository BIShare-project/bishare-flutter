# BIShare Vault — key and wire specification, version 1

The storage product ("BIShare Drive" to people, `vault` in code). This file is
the one definition of every key, envelope and signature the vault uses. Three
implementations exist and must agree byte for byte:

- Rust, `src/vault.rs` in this crate (the canonical one; the app reaches it
  through flutter_rust_bridge),
- TypeScript, `bishare-web/src/lib/vault/crypto.ts` (the browser; the API
  worker verifies signatures and sign-in nonces with the same rules),
- and the vectors that pin them: `bishare-flutter/test/fixtures/vault_vectors.json`,
  written by the Rust tests and copied to `bishare-web/src/lib/vault/vault-vectors.json`.

A change here is a change to all three and to the vectors.

## Notation

```
b64u(x)        base64url without padding (RFC 4648 §5, no "=")
utf8(s)        the UTF-8 bytes of s
a ‖ b          concatenation
HKDF(ikm, info, n)
               HKDF-SHA256 (RFC 5869), salt = 32 bytes of 0x00, output n bytes.
               Where a salt is named, it replaces the zero salt.
AEAD(key, nonce, plain, aad)
               AES-256-GCM; the output is ciphertext ‖ 16-byte tag.
box(key, plain, aad)
               nonce ‖ AEAD(key, nonce, plain, aad), nonce = 12 random bytes.
               Opening a box shorter than 28 bytes, or whose tag fails, is an error.
SHA256(x)      the 32-byte digest
seq(n, b)      in the vectors: n bytes b, b+1, b+2, … (mod 256)
```

Every key is 32 bytes. Every nonce is 12 random bytes made by the sealing side
and never reused under the same key; the tests fix nonces to make the vectors
reproducible, production code never does.

## Identifiers

| Name | Bytes | Text form |
|---|---|---|
| vault id | 16 random bytes made by the server when the account is created | lowercase RFC 4648 base32, no padding: 26 characters of `a-z2-7` |
| object id | 16 random bytes made by the device that creates the object | b64u, 22 characters |
| device id | `SHA256(device public key)[0..16)` | b64u, 22 characters |

A client checks the text form before using an id in an AAD string: a vault id
is exactly 26 characters of `[a-z2-7]`, an object id decodes to 16 bytes.

## Keys

```
VK              the vault key: 32 random bytes, made on the first device of the account
key check       b64u(HKDF(VK, "bishare-vault-kid-v1", 16))
                registered with the server when VK is made. A device that receives a
                VK by any path checks it against the server's value and refuses a mismatch.
K_meta          HKDF(VK, "bishare-vault-meta-v1", 32)
phrase          the BIP-39 English mnemonic of VK: 24 words, lowercase, single spaces
file key        32 random bytes per file object; the BSE2 key for the file's bytes
thumb key       HKDF(file key, "bishare-vault-thumb-v1", 32)
K_dedupe        HKDF(VK, "bishare-vault-dedupe-v1", 32)
device key      an Ed25519 key pair (RFC 8032) made on each device from a 32-byte
                random seed; the seed never leaves the device
```

The phrase is read back after NFKD normalization, lower-casing and collapsing
whitespace; the BIP-39 checksum must hold and the word count must be 24, so a
phrase decodes to exactly 32 bytes or fails.

## The key copy (recovery through the person's own account)

A copy of VK that lives in the person's Apple or Google account, readable only
with a value the server hands to a device that has just signed in.

```
server half     32 random bytes made by the server for the account, returned to a
                device only in the response to a successful sign-in
backup key      HKDF(server half, "bishare-vault-backup-v1", 32)
key copy        "BSVK" ‖ 0x01 ‖ nonce ‖ AEAD(backup key, nonce, VK, aad = utf8(vault id))
                = 4 + 1 + 12 + 32 + 16 = 65 bytes
```

A reader rejects anything but 65 bytes starting with `BSVK` `0x01`, then
opens the box. Neither the account provider (which holds the copy) nor the
server (which holds the half) can open it alone.

## Object metadata

Everything a person would recognise about a file or folder is sealed under
`K_meta`; the server stores the sealed string and never a name.

```
enc_meta        b64u(box(K_meta, utf8(JSON), aad = utf8("bishare-vault-meta-v1|" ‖ vault id ‖ "|" ‖ object id)))
```

The JSON is one object. A writer emits exactly these keys, in this order, with
no whitespace, and omits a key that does not apply:

| Key | Value | Present for |
|---|---|---|
| `v` | `1` | both |
| `k` | `"file"` or `"dir"` | both |
| `n` | the name, as typed; never empty, no `/`, no U+0000 | both |
| `p` | the parent object id, or `null` at the root | both (always written) |
| `m` | modification time, integer Unix milliseconds | both |
| `s` | plaintext size in bytes, integer | file |
| `t` | MIME type, never empty | file |
| `fk` | b64u(file key) | file |
| `h` | b64u(SHA256(plaintext)) | file |
| `z` | `"deflate"`, only when the blob holds the bytes compressed (see "Compression") | file, optional |

A reader accepts any JSON serialization and ignores keys it does not know,
rejects `v` ≠ 1, an unknown `k`, a bad name, a file without all four of
`s`, `t`, `fk`, `h` or whose `fk` or `h` is not 32 bytes, and a file whose
`z` is anything but `"deflate"` (bytes it could not read back). A folder
never carries `z`. Strings are UTF-8
and are not normalized by either side.

The AAD binds the sealed metadata to one object of one vault: moving a sealed
string to another object, or to another vault, fails to open.

## Compression (added 2026-10-21)

A writer may compress a file before sealing it, to keep stored bytes down
(drive-plan.md "Keeping R2 cost down"). The only method is raw DEFLATE
(RFC 1951: no zlib or gzip header), and the sealed metadata says so with
`"z":"deflate"`:

```
blob            BSE2(file key, DEFLATE(plaintext))
s, h            the size and SHA-256 of the plaintext, not of the compressed bytes
```

Any DEFLATE encoder may write it (the Rust code uses miniz_oxide at level 6,
the browser `CompressionStream("deflate-raw")`); a reader accepts any valid
stream. A reader inflates to at most `s` bytes and refuses a stream that
gives more or fewer, so a crafted stream cannot expand without bound.

When to compress is a writer's choice, not part of the format: only types
that are not already compressed (documents, text, code, CSV, uncompressed
audio and images, PSD), and only when the result is at least 10% smaller.
Maximum security writes no `z`, so stored sizes say nothing about how
compressible a file is.

## Copies stored once: the dedupe tag (added 2026-10-21)

```
dedupe tag      b64u(HMAC-SHA256(K_dedupe, h)[0..16))      h = the 32-byte SHA-256 of the plaintext
```

Sent with an upload. The server answers with a blob of the same vault that
has the same tag and ciphertext size, if one exists; the new object then
points at that blob and copies its file key from the object that already
does. `K_dedupe` is derived from VK, so the tag of a file differs in every
vault and cannot be used to ask whether some other vault holds a known file.
What the server learns is that two objects in one vault have the same
content. Maximum security sends no tag.

## Thumbnails

```
enc_thumb       box(thumb key, jpeg, aad = utf8("bishare-vault-thumb-v1|" ‖ vault id ‖ "|" ‖ object id))
```

Stored as raw bytes, not b64u. A thumbnail opens only with the file key of its
own object, so a device that can list a folder but has not fetched a file's
metadata cannot show its picture.

## Device names (added 2026-10-21)

```
enc_name        b64u(box(K_meta, utf8(name), aad = utf8("bishare-vault-device-v1|" ‖ vault id ‖ "|" ‖ device id)))
```

The name a person gives a device ("Cakra's iPhone"), set with the
`device_name` op and shown in the device list. Sealed like `enc_meta`, so the
server stores names it cannot read. A writer emits 1 to 100 characters with
no U+0000; a reader rejects an empty name and a name with U+0000. The AAD
binds the name to one device of one vault.

## Handing the vault key to another device (the grant)

Used when a device cannot reach the key copy. Both sides make a fresh X25519
key pair for one hand-off; neither key is kept. This is the room grant of
`bishare-web/src/lib/rooms/e2e.ts` with the vault's labels.

```
new device      newPriv, newPub = X25519 key pair; newPub travels in a QR code
granter         granterPriv, granterPub = X25519 key pair; granterPub travels with the box
shared          X25519(granterPriv, newPub) = X25519(newPriv, granterPub);
                a shared secret of all zero bytes is refused
wrap key        HKDF(shared, salt = newPub ‖ granterPub, "bishare-vault-grant-v1", 32)
grant box       box(wrap key, VK, aad = utf8(vault id))
```

The new device opens the box, derives the key check and compares it with the
server's. Only then is VK accepted.

## Signed requests

Every request to `/api/v1/vault/*` other than sign-in carries one header:

```
Authorization: BIShare-Vault v=1,vault=<vault id>,device=<device id>,ts=<ts>,sig=<b64u(signature)>
```

`ts` is the device's clock, integer Unix seconds. Fields are separated by a
comma with no spaces, in this order. The signature is Ed25519 over the UTF-8
bytes of

```
"bishare-vault-req-v1" ‖ "\n" ‖ METHOD ‖ "\n" ‖ PATH ‖ "\n" ‖ ts ‖ "\n" ‖ hex(SHA256(body))
```

- `METHOD` is upper case.
- `PATH` is the request path followed by `?` and the query string exactly as
  sent, or the path alone when there is no query. No normalization.
- `body` is the raw request body; an empty body hashes to
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- `hex` is lower case.

The server looks the device public key up by `vault` and `device`, verifies
the signature, and rejects a `ts` more than 300 seconds from its own clock.
Replay inside that window is handled by the request's own idempotency key
(`op_id`), not by the signature.

## Sign-in nonce

The ID token a device presents at sign-in carries a nonce the server checks
against the device public key sent with it, so a token taken from one device
cannot enrol another:

```
nonce           b64u(SHA256(utf8("bishare-vault-nonce-v1") ‖ device public key))
```

The same string is passed to Apple and Google as the request nonce and comes
back unchanged as the token's `nonce` claim.

## Error handling, both sides

A box that fails to open, a key copy with the wrong magic, a phrase with a bad
checksum, a signature that does not verify: each is an error the caller sees
by category and never by partial output. Nothing in this spec returns
plaintext from a failed authentication.

## Vectors

`vault_vectors.json` fixes every random input (`seq` values) and records every
derived value: key check, `K_meta`, phrase, key copy, device public key and
id, sign-in nonce, a signed request with its message and header, a sealed
file and folder entry, a sealed thumbnail, a grant, `K_dedupe` with the
dedupe tag of the file, and a compressed file (its plaintext, the DEFLATE
stream Rust wrote, and its sealed entry with `z`). The Rust tests write
the file; the Dart and TypeScript tests must reproduce every value and must
also fail on a flipped bit, a wrong vault id in an AAD, a wrong key check and
a stale phrase checksum.
