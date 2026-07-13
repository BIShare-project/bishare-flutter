//! QUIC transport (Flutter↔Flutter) via `quinn`. A single QUIC connection carries
//! one **bidirectional stream per file** (no head-of-line blocking, zero handshake
//! per stream). Confirmed delivery: the receiver ACKs one byte per file.
//!
//! Division of labour (matches the TCP path's design):
//!   * **Rust/QUIC** is the fast pipe — it streams the file straight to a `.part`
//!     temp file in the save dir and emits a rich event.
//!   * **Dart** owns consent (accept/reject happens over TCP `prepare` first),
//!     final naming/categorisation, history and the received-file stream.
//!
//! No app-layer E2E over QUIC — TLS 1.3 is the encryption (mirrors native, which
//! sets `shouldEncrypt = key != nil && !useQUIC`). Client skips cert verification
//! (trusted LAN), matching native's `sec_protocol_options_set_verify_block(true)`.
//!
//! Stream wire format (per file):
//!   `[str sessionId][str fileId][str senderAlias][str senderFingerprint]`
//!   `[str fileName][str fileType][u64 size][size bytes]`
//! where `str` = `[u32 len][utf8 bytes]`. Reply: 1 ACK byte.

use std::collections::HashMap;
use std::net::{Ipv6Addr, SocketAddr};
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::OnceLock;

use crate::engine::bufpool::pool;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use quinn::crypto::rustls::{QuicClientConfig, QuicServerConfig};
use quinn::{ClientConfig, Endpoint, ServerConfig};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime;

const ALPN: &[u8] = b"bishare-quic";
const READ_CHUNK: usize = 1024 * 1024;
const MAX_STR: usize = 8192;

/// Per-read idle timeout (Phase 0). A peer that opens a stream — or sends the
/// header — and then stalls must NOT pin a tokio task + a `.part` file forever.
/// This is the real defence, not quinn's idle-timeout: `keep_alive_interval(5s)`
/// keeps the connection idle-timer from ever firing while the peer *process* is
/// alive, so a pure app-layer stall (header sent, body withheld) would otherwise
/// block indefinitely. Every network read is bounded by this.
const IDLE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);

/// Coalesce progress callbacks to ~30 Hz. The hot loop reads/writes 1 MB
/// (`READ_CHUNK`) at a time → ~900 callbacks/s at 900 MB/s; throttling to one per
/// ~33 ms keeps the FRB sink (and Dart UI) from being flooded.
const PROGRESS_INTERVAL: std::time::Duration = std::time::Duration::from_millis(33);

// ── Multi-stream wire format (Phase 1b) ──────────────────────────────────────
//
// Negotiated via `PrepareResponse.streamsPerFile` (receiver-authoritative): the
// sender only uses this format when the receiver advertised it; otherwise it
// sends the byte-identical legacy single-stream body. On the wire, the first u32
// of every stream disambiguates: legacy streams start with the sessionId string
// length (≤ MAX_STR = 8192), so any value above that is safe as a format tag.
//
// Control stream (one per file, bidi; carries the legacy 6-string header + file
// geometry, and the receiver's 1-byte ACK on completion):
//   [u32 MAGIC_CONTROL][6 strings][u64 size][u32 chunkSize][u8 streamCount]
// Data streams (streamCount per file, bidi; receiver never writes on them):
//   [u32 MAGIC_DATA][str sessionId][str fileId]
//   then repeated: [u64 absOffset][u32 payloadLen][u32 crc32c][u8 flags][payload]
// `absOffset = chunkIndex * chunkSize` is self-describing, so cross-stream
// ordering is irrelevant: the receiver pwrite()s each chunk in place and tracks
// completion in a chunk bitmap (hte-architecture.md §2.3/§3).
const MAGIC_CONTROL: u32 = 0xB15A_C701;
/// Resume-capable control stream (Phase 4). Header adds a trailing `[str
/// resumeKey]`, and after it the RECEIVER writes back a have-bitmap so the
/// sender skips already-received chunks. Gated by `PrepareResponse.supportsResume`
/// so a v1 peer (which never advertises it) is never sent this magic.
const MAGIC_CONTROL_V2: u32 = 0xB15A_C703;
const MAGIC_DATA: u32 = 0xB15A_DA7A;

/// Frame flags (bit0 = compressed, bit1 = app-layer-encrypted). Both 0 in 1b.
const FRAME_FLAGS_NONE: u8 = 0;

/// Bounds for the negotiated per-file geometry, mirroring the protocol crate.
const MIN_CHUNK: u32 = bishare_protocol::constants::Config::MIN_CHUNK_SIZE as u32; // 64 KB
const MAX_CHUNK: u32 = bishare_protocol::constants::Config::MAX_CHUNK_SIZE as u32; // 1 MB
/// Max data streams per file. Capped at 8 (not 32) to stay inside the buffer
/// pool's reachable envelope (16 slabs shared by send+receive; hte §5 / bufpool
/// docs): 8 concurrent per-chunk slabs per direction. A peer negotiating more is
/// clamped to this on both send and receive.
const MAX_STREAMS: u8 = 8;

/// Validate one data-frame header against the file geometry established by the
/// control stream. Returns the chunk index. Pure — unit-tested exhaustively
/// (this parses attacker-controlled u64/u32 fields off the network).
fn validate_chunk(
    abs_offset: u64,
    payload_len: u32,
    chunk_size: u32,
    file_size: u64,
) -> Result<u64, String> {
    if payload_len == 0 || payload_len > chunk_size {
        return Err(format!("bad payload len {payload_len} (chunk {chunk_size})"));
    }
    if abs_offset % chunk_size as u64 != 0 {
        return Err(format!("misaligned offset {abs_offset}"));
    }
    if abs_offset >= file_size {
        return Err(format!("offset {abs_offset} beyond size {file_size}"));
    }
    // Overflow-safe: abs_offset < file_size, payload_len ≤ 1 MB.
    if abs_offset + payload_len as u64 > file_size {
        return Err(format!(
            "chunk overruns file: {abs_offset}+{payload_len} > {file_size}"
        ));
    }
    let idx = abs_offset / chunk_size as u64;
    // Every chunk except the last must be exactly chunk_size; the last must
    // reach exactly EOF. Rejects short/gappy interior chunks up front.
    let expected = (file_size - abs_offset).min(chunk_size as u64) as u32;
    if payload_len != expected {
        return Err(format!(
            "chunk {idx} len {payload_len}, expected {expected}"
        ));
    }
    Ok(idx)
}

/// Positional write of the whole buffer (pwrite-style; no shared cursor).
fn write_all_at(file: &std::fs::File, buf: &[u8], offset: u64) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::FileExt::write_all_at(file, buf, offset)
    }
    #[cfg(windows)]
    {
        let (mut buf, mut offset) = (buf, offset);
        while !buf.is_empty() {
            let n = std::os::windows::fs::FileExt::seek_write(file, buf, offset)?;
            buf = &buf[n..];
            offset += n as u64;
        }
        Ok(())
    }
}

/// Positional read of exactly `buf.len()` bytes.
fn read_exact_at(file: &std::fs::File, buf: &mut [u8], offset: u64) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::FileExt::read_exact_at(file, buf, offset)
    }
    #[cfg(windows)]
    {
        let (mut buf, mut offset) = (&mut buf[..], offset);
        while !buf.is_empty() {
            let n = std::os::windows::fs::FileExt::seek_read(file, buf, offset)?;
            if n == 0 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "eof in read_exact_at",
                ));
            }
            buf = &mut buf[n..];
            offset += n as u64;
        }
        Ok(())
    }
}

/// Shared multi-thread tokio runtime that drives all QUIC I/O.
fn runtime() -> &'static Runtime {
    static RT: OnceLock<Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to build QUIC tokio runtime")
    })
}

// ---------------------------------------------------------------------------
// TLS config
// ---------------------------------------------------------------------------

fn self_signed() -> Result<(CertificateDer<'static>, PrivateKeyDer<'static>), String> {
    let ck = rcgen::generate_simple_self_signed(vec!["bishare".to_string()])
        .map_err(|e| format!("cert gen: {e}"))?;
    let cert = CertificateDer::from(ck.cert);
    let key = PrivateKeyDer::from(PrivatePkcs8KeyDer::from(ck.key_pair.serialize_der()));
    Ok((cert, key))
}

/// Accept any server cert — trusted-LAN posture, matching native.
#[derive(Debug)]
struct SkipServerVerify(Arc<rustls::crypto::CryptoProvider>);

impl rustls::client::danger::ServerCertVerifier for SkipServerVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

fn ring_provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Flow-control + keep-alive + MTU tuning (Phase 2a, hte-architecture.md §5/§8).
///
/// Windows are sized ≥2× the worst realistic LAN BDP while staying far under the
/// RAM gate — quinn's windows are the DOMINANT data-plane RAM term, not the slab
/// pool. LAN RTT is sub-ms (WiFi ~2–5 ms): even 10 Gbps × 1 ms = 1.25 MB BDP, so
/// 4 MB/stream is ≥3× headroom and 32 MB/connection covers 8 streams at full
/// tilt. (The previous 16/64/64 MB let a single connection buffer ~128 MB.)
/// Worst-case data-plane RAM ≈ pool 16 + recv 32 + send 32 ≈ 80 MB.
///
/// MTU: DPLPMTUD probes up to jumbo (9000) — a real win on wired LAN and
/// especially Apple (no UDP GSO → per-datagram syscalls; bigger datagrams cut
/// the syscall rate ~6×). quinn's built-in blackhole detection falls back to the
/// base MTU on paths that silently drop large packets (VPN/tunnels), so this is
/// safe to enable unconditionally.
fn transport_config() -> Arc<quinn::TransportConfig> {
    let mut t = quinn::TransportConfig::default();
    t.stream_receive_window(quinn::VarInt::from_u32(4 * 1024 * 1024)); // 4 MB / stream
    t.receive_window(quinn::VarInt::from_u32(32 * 1024 * 1024)); // 32 MB / connection
    t.send_window(32 * 1024 * 1024);
    let mut mtu = quinn::MtuDiscoveryConfig::default();
    mtu.upper_bound(9000); // probe toward jumbo frames on wired LAN
    t.mtu_discovery_config(Some(mtu));
    t.max_idle_timeout(Some(
        std::time::Duration::from_secs(30).try_into().unwrap(),
    ));
    t.keep_alive_interval(Some(std::time::Duration::from_secs(5)));
    Arc::new(t)
}

/// Build a UDP socket with LARGE send/recv buffers (best-effort 4 MB) — the OS
/// defaults (macOS ≈64 KB) overflow at our burst rates: the Phase 3 benchmark
/// measured **7% packet loss on loopback** purely from buffer overruns, which
/// both wastes ~7% of goodput on retransmits AND stalls DPLPMTUD (lost probes
/// read as "MTU too big", pinning the search at ~1472).
fn make_udp_socket(addr: SocketAddr) -> Result<std::net::UdpSocket, String> {
    let domain = if addr.is_ipv6() {
        socket2::Domain::IPV6
    } else {
        socket2::Domain::IPV4
    };
    let sock = socket2::Socket::new(domain, socket2::Type::DGRAM, Some(socket2::Protocol::UDP))
        .map_err(|e| e.to_string())?;
    const BUF: usize = 4 * 1024 * 1024;
    let _ = sock.set_recv_buffer_size(BUF); // best-effort (kernel may clamp)
    let _ = sock.set_send_buffer_size(BUF);
    if addr.is_ipv6() {
        let _ = sock.set_only_v6(false); // dual-stack like Endpoint defaults
    }
    sock.bind(&addr.into()).map_err(|e| e.to_string())?;
    sock.set_nonblocking(true).map_err(|e| e.to_string())?;
    Ok(sock.into())
}

/// Server endpoint on a buffer-tuned socket.
fn tuned_server_endpoint(cfg: ServerConfig, addr: SocketAddr) -> Result<Endpoint, String> {
    Endpoint::new(
        quinn::EndpointConfig::default(),
        Some(cfg),
        make_udp_socket(addr)?,
        Arc::new(quinn::TokioRuntime),
    )
    .map_err(|e| e.to_string())
}

/// Client endpoint on a buffer-tuned socket.
fn tuned_client_endpoint(addr: SocketAddr) -> Result<Endpoint, String> {
    Endpoint::new(
        quinn::EndpointConfig::default(),
        None,
        make_udp_socket(addr)?,
        Arc::new(quinn::TokioRuntime),
    )
    .map_err(|e| e.to_string())
}

fn client_config() -> Result<ClientConfig, String> {
    let provider = ring_provider();
    let mut tls = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| format!("tls: {e}"))?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SkipServerVerify(provider)))
        .with_no_client_auth();
    tls.alpn_protocols = vec![ALPN.to_vec()];
    let quic = QuicClientConfig::try_from(tls).map_err(|e| format!("quic client: {e}"))?;
    let mut cfg = ClientConfig::new(Arc::new(quic));
    cfg.transport_config(transport_config());
    Ok(cfg)
}

fn server_config() -> Result<ServerConfig, String> {
    let (cert, key) = self_signed()?;
    let mut tls = rustls::ServerConfig::builder_with_provider(ring_provider())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| format!("tls: {e}"))?
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)
        .map_err(|e| format!("server cert: {e}"))?;
    tls.alpn_protocols = vec![ALPN.to_vec()];
    let quic = QuicServerConfig::try_from(tls).map_err(|e| format!("quic server: {e}"))?;
    let mut cfg = ServerConfig::with_crypto(Arc::new(quic));
    cfg.transport_config(transport_config());
    Ok(cfg)
}

// ---------------------------------------------------------------------------
// Length-prefixed string helpers
// ---------------------------------------------------------------------------

async fn write_str(send: &mut quinn::SendStream, s: &str) -> Result<(), String> {
    send.write_u32(s.len() as u32).await.map_err(|e| e.to_string())?;
    send.write_all(s.as_bytes()).await.map_err(|e| e.to_string())?;
    Ok(())
}

async fn read_str(recv: &mut quinn::RecvStream) -> Result<String, String> {
    let len = recv.read_u32().await.map_err(|e| e.to_string())? as usize;
    read_str_body(recv, len).await
}

/// Read a string whose u32 length prefix has already been consumed — used by the
/// stream dispatcher, which reads the first u32 to tell magic-tagged multi-stream
/// frames apart from a legacy stream's first string length.
async fn read_str_body(recv: &mut quinn::RecvStream, len: usize) -> Result<String, String> {
    if len > MAX_STR {
        return Err(format!("string too long: {len}"));
    }
    let mut buf = vec![0u8; len];
    recv.read_exact(&mut buf).await.map_err(|e| e.to_string())?;
    Ok(String::from_utf8_lossy(&buf).to_string())
}

/// Merkle root over per-chunk SHA-256 leaves (Phase 1d whole-file integrity for
/// the multi-stream path). Root = SHA-256 of the leaf digests concatenated in
/// canonical chunk-index order, so it is INDEPENDENT of the order chunks arrive
/// across streams — the receiver hashes each chunk on arrival and combines at the
/// end, never re-reading the file. Both peers compute it identically.
fn merkle_root(leaves: &[[u8; 32]]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    for leaf in leaves {
        h.update(leaf);
    }
    h.finalize().into()
}

/// SHA-256 of one chunk (a Merkle leaf).
fn sha256_leaf(data: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    Sha256::digest(data).into()
}

/// Session-scoped `.part` temp filename, sanitised. Session-scoping prevents a
/// re-send or a concurrent transfer of the same fileId (different session) from
/// colliding on the same partial file.
fn part_name(session_id: &str, file_id: &str) -> String {
    let safe = |s: &str| -> String {
        s.chars().filter(|c| c.is_alphanumeric() || *c == '-').collect()
    };
    format!(".quic-{}-{}.part", safe(session_id), safe(file_id))
}

/// Resume-scoped `.part` name (Phase 4): keyed by the STABLE resume key (not the
/// per-transfer session), so a reconnect under a fresh session finds its partial.
fn resume_part_name(resume_key: &str) -> String {
    let safe: String = resume_key
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
        .collect();
    format!(".quic-r-{safe}.part")
}

/// Removes a resume key from the active set on drop (all control_recv exits).
#[frb(ignore)]
struct ActiveKeyGuard(Option<String>);
impl Drop for ActiveKeyGuard {
    fn drop(&mut self) {
        if let Some(k) = self.0.take() {
            active_resume_keys().lock().unwrap().remove(&k);
        }
    }
}

/// Re-hash the chunks a resumed `.part` already holds (their leaves were lost
/// when the previous session's RAM state was dropped) so the final Merkle root
/// covers the whole file. Reads from disk only — the network re-send is what
/// resume avoids. A disk-corrupted partial simply fails the final verify and
/// restarts clean.
async fn rehash_have_chunks(state: &Arc<RecvFileState>) -> Result<(), String> {
    let (chunk_size, file_size, total) =
        (state.chunk_size, state.file_size, state.total_chunks);
    let have: Vec<u64> = {
        let bm = state.bitmap.lock().unwrap();
        (0..total).filter(|&i| bm.has(i)).collect()
    };
    for idx in have {
        let offset = idx * chunk_size as u64;
        let len = (file_size - offset).min(chunk_size as u64) as usize;
        let file = state.file.clone();
        let leaf = tokio::task::spawn_blocking(move || -> std::io::Result<[u8; 32]> {
            let mut buf = vec![0u8; len];
            read_exact_at(&file, &mut buf, offset)?;
            Ok(sha256_leaf(&buf))
        })
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())?;
        state.leaves.lock().unwrap()[idx as usize] = leaf;
    }
    Ok(())
}

/// Run `fut`, failing with an idle-timeout error if it does not finish within `d`.
async fn idle<T>(
    d: std::time::Duration,
    fut: impl std::future::Future<Output = Result<T, String>>,
) -> Result<T, String> {
    match tokio::time::timeout(d, fut).await {
        Ok(r) => r,
        Err(_) => Err("idle timeout".to_string()),
    }
}

/// Bounded stream write. quinn's `write_all` suspends indefinitely once the
/// peer's flow-control window is exhausted, and keep-alive stops the connection
/// idle-timeout from ever firing while both processes live — so a receiver that
/// stalls (without dying) would otherwise pin the sender task AND the slab it
/// holds forever (the cross-direction deadlock found in the Phase 1c review).
/// Generous (5× the read idle timeout) because a full window can legitimately
/// take a while to drain on a slow link.
async fn write_all_bounded(send: &mut quinn::SendStream, buf: &[u8]) -> Result<(), String> {
    match tokio::time::timeout(IDLE_TIMEOUT * 5, send.write_all(buf)).await {
        Ok(r) => r.map_err(|e| e.to_string()),
        Err(_) => Err("send stalled (flow-control timeout)".to_string()),
    }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Events streamed from the QUIC server to Dart.
#[derive(Clone)]
pub enum QuicServerEvent {
    /// The server is listening.
    Ready,
    /// A file arrived, written to `temp_path`. Dart names/records it.
    Received {
        session_id: String,
        file_id: String,
        sender_alias: String,
        sender_fingerprint: String,
        file_name: String,
        file_type: String,
        temp_path: String,
        size: u64,
        /// Phase 1d: the received bytes were integrity-verified against the
        /// sender's whole-file hash (Merkle root on multi-stream, streaming
        /// SHA-256 on legacy). Replaces the old hardcoded flag — Dart records
        /// this as the real `verified` result.
        verified: bool,
    },
    /// Incremental receive progress, emitted while the body streams in so the
    /// receiver UI advances instead of sitting on "Starting…" until completion.
    Progress {
        session_id: String,
        file_id: String,
        file_name: String,
        received: u64,
        total: u64,
    },
    /// A non-fatal receive error. `session_id`/`file_id` are set when the
    /// failure happened after the stream identified itself — Dart uses them to
    /// clear the session's progress card (e.g. when the SENDER cancels
    /// mid-transfer, the stream reset lands here and must not leave a stale
    /// floating card on the receiver).
    Error {
        message: String,
        session_id: Option<String>,
        file_id: Option<String>,
    },
}

/// A receive failure with as much session context as was parsed before the
/// failure — so the UI can clear the right progress card. `From<String>` keeps
/// `?` ergonomic for early failures where no context exists yet.
#[frb(ignore)]
#[derive(Debug)]
struct RecvFailure {
    session_id: Option<String>,
    file_id: Option<String>,
    message: String,
}

impl From<String> for RecvFailure {
    fn from(message: String) -> Self {
        Self { session_id: None, file_id: None, message }
    }
}

/// Attach session/file context to any plain-String failure from `res`.
fn with_ctx<T>(
    res: Result<T, String>,
    session_id: &str,
    file_id: Option<&str>,
) -> Result<T, RecvFailure> {
    res.map_err(|message| RecvFailure {
        session_id: Some(session_id.to_string()),
        file_id: file_id.map(|f| f.to_string()),
        message,
    })
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

/// Registry of running server endpoints by port, so [quic_stop] can close one
/// (FRB drops a function's return value when it also takes a StreamSink, so the
/// server can't be handed back as an opaque handle).
fn servers() -> &'static Mutex<HashMap<u16, Endpoint>> {
    static S: OnceLock<Mutex<HashMap<u16, Endpoint>>> = OnceLock::new();
    S.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Stop the QUIC server on [port], if one is running.
#[frb(sync)]
pub fn quic_stop(port: u16) {
    if let Some(ep) = servers().lock().unwrap().remove(&port) {
        ep.close(0u32.into(), b"bye");
    }
}

/// Per-transfer control state, modelled as an atomic bitset so the hot send loop
/// reads it lock-free each chunk. Only `CANCELLED` is wired today; `PAUSED` is
/// reserved for the persistent-engine pause/resume (Phase 4) so it can hang off
/// the same registry entry without a second registry.
///
/// `#[frb(ignore)]`: this is a pure Rust-side impl detail — it must NOT be
/// exposed across the FFI as an opaque Dart type (Dart drives it only via the
/// `quic_cancel` function).
#[frb(ignore)]
#[derive(Default)]
struct ControlState {
    flags: std::sync::atomic::AtomicU8,
}

impl ControlState {
    const CANCELLED: u8 = 0b01;
    #[allow(dead_code)] // reserved for engine pause/resume (Phase 4)
    const PAUSED: u8 = 0b10;

    fn set(&self, bit: u8) {
        self.flags
            .fetch_or(bit, std::sync::atomic::Ordering::Relaxed);
    }

    fn has(&self, bit: u8) -> bool {
        self.flags.load(std::sync::atomic::Ordering::Relaxed) & bit != 0
    }
}

/// Control-state registry keyed by transfer id (the sender uses the sessionId).
/// Replaces the old cancel-only `HashSet` so pause/resume can reuse the entry.
fn controls() -> &'static Mutex<HashMap<String, Arc<ControlState>>> {
    static C: OnceLock<Mutex<HashMap<String, Arc<ControlState>>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Fetch (creating if absent) the control state for [id]. Resolve once per send
/// and check the returned `Arc` per chunk — never re-lock the registry in the loop.
fn control_for(id: &str) -> Arc<ControlState> {
    controls()
        .lock()
        .unwrap()
        .entry(id.to_string())
        .or_default()
        .clone()
}

/// Cancel the in-flight QUIC send tagged with [cancel_id].
#[frb(sync)]
pub fn quic_cancel(cancel_id: String) {
    control_for(&cancel_id).set(ControlState::CANCELLED);
}

/// Transfer buffer-pool stats (Phase 1c hard RAM ceiling), for field diagnostics:
/// `"slabs=<cap> allocated=<n> in_use=<n> peak=<n> acquires=<n>"`. `allocated`
/// never exceeding `slabs` — no matter how much data has moved — is the proof
/// that data-plane RAM is independent of file size.
#[frb(sync)]
pub fn quic_buffer_pool_stats() -> String {
    let (cap, allocated, in_use, peak, acquires) = pool().stats();
    format!("slabs={cap} allocated={allocated} in_use={in_use} peak={peak} acquires={acquires}")
}

/// Live path/transport stats for the session's connection as compact JSON
/// (Phase 3 metrics): RTT, cwnd, the ACTUAL DPLPMTUD-negotiated MTU, congestion
/// events, loss, UDP datagram/syscall counts, pool counters, HW-AES flag.
/// Returns "{}" if the session has no live connection.
#[frb(sync)]
pub fn quic_session_stats(session_id: String) -> String {
    let conn = connections()
        .lock()
        .unwrap()
        .get(&session_id)
        .map(|sc| sc.conn.clone());
    match conn {
        Some(c) => crate::engine::metrics::conn_stats_json(&c),
        None => "{}".to_string(),
    }
}

/// Loopback benchmark (Phase 3): pushes `size_mb` of generated data through the
/// FULL multi-stream pipeline — pread → CRC32C → SHA-256 leaves → framing →
/// quinn TLS 1.3 over 127.0.0.1 → validate → CRC → pwrite → Merkle verify → ACK
/// — entirely in-process, and returns one JSON line. This measures this
/// device's CPU/pipeline CEILING (no real network): the honest upper bound any
/// LAN transfer could reach on this hardware (hte-architecture.md §18 Phase 3
/// exit: "loopback figure labeled as the CPU/pipeline ceiling").
pub fn quic_benchmark(size_mb: u32, streams: u8, chunk_kb: u32) -> Result<String, String> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static BENCH_SEQ: AtomicU64 = AtomicU64::new(0);
    let size_mb = size_mb.clamp(1, 2048);
    let streams = streams.clamp(1, MAX_STREAMS);
    let chunk_size = (chunk_kb * 1024).clamp(MIN_CHUNK, MAX_CHUNK);
    let session = format!(
        "bench-{}-{}",
        std::process::id(),
        BENCH_SEQ.fetch_add(1, Ordering::Relaxed)
    );
    quic_authorize_session(session.clone());

    let out = runtime().block_on(async {
        let dir = std::env::temp_dir().join(format!("bishare_bench_{session}"));
        tokio::fs::create_dir_all(&dir).await.map_err(|e| e.to_string())?;
        let src = dir.join("bench.bin");
        // Generate the payload in 1 MB slices (never hold it in RAM).
        {
            let mut f = tokio::fs::File::create(&src).await.map_err(|e| e.to_string())?;
            let mut slice = vec![0u8; 1024 * 1024];
            for m in 0..size_mb as usize {
                for (i, b) in slice.iter_mut().enumerate() {
                    *b = ((m * 31 + i / 13) % 251) as u8;
                }
                tokio::io::AsyncWriteExt::write_all(&mut f, &slice)
                    .await
                    .map_err(|e| e.to_string())?;
            }
        }

        // In-process receiver: one connection, dispatch every stream.
        let server_ep = tuned_server_endpoint(server_config()?, "127.0.0.1:0".parse().unwrap())?;
        let port = server_ep.local_addr().map_err(|e| e.to_string())?.port();
        let dir_recv = dir.to_string_lossy().to_string();
        let server = runtime().spawn(async move {
            let conn = server_ep
                .accept()
                .await
                .ok_or("bench accept failed".to_string())?
                .await
                .map_err(|e| e.to_string())?;
            let (tx, mut rx) =
                tokio::sync::mpsc::unbounded_channel::<Result<QuicServerEvent, String>>();
            loop {
                tokio::select! {
                    ev = rx.recv() => {
                        let ev = ev.ok_or("bench event channel closed".to_string())??;
                        conn.closed().await;
                        return Ok::<QuicServerEvent, String>(ev);
                    }
                    accepted = conn.accept_bi() => {
                        let (send, recv) = accepted.map_err(|e| e.to_string())?;
                        let dir = dir_recv.clone();
                        let tx = tx.clone();
                        runtime().spawn(async move {
                            match stream_dispatch(send, recv, &dir, None, IDLE_TIMEOUT).await {
                                Ok(Some(ev)) => { let _ = tx.send(Ok(ev)); }
                                Ok(None) => {}
                                Err(f) => { let _ = tx.send(Err(f.message)); }
                            }
                        });
                    }
                }
            }
        });

        let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap())?;
        client_ep.set_default_client_config(client_config()?);
        let conn = client_ep
            .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
            .map_err(|e| e.to_string())?
            .await
            .map_err(|e| e.to_string())?;
        let control = Arc::new(ControlState::default());

        let started = tokio::time::Instant::now();
        let sent = stream_send_multi(
            &conn,
            &control,
            &session,
            "bench-file",
            "bench",
            "bench",
            &src.to_string_lossy(),
            "bench.bin",
            "application/octet-stream",
            streams,
            chunk_size,
            None,
            |_| {},
        )
        .await?;
        let elapsed_ms = started.elapsed().as_millis() as u64;
        let stats = crate::engine::metrics::conn_stats_json(&conn);

        conn.close(0u32.into(), b"done");
        client_ep.wait_idle().await;
        let ev = server.await.map_err(|e| e.to_string())??;
        let verified = matches!(ev, QuicServerEvent::Received { verified: true, .. });

        let _ = tokio::fs::remove_dir_all(&dir).await;
        let mbps = if elapsed_ms > 0 {
            (sent as f64 / (1024.0 * 1024.0)) / (elapsed_ms as f64 / 1000.0)
        } else {
            0.0
        };
        Ok(format!(
            "{{\"mbps\":{mbps:.1},\"elapsed_ms\":{elapsed_ms},\"size_mb\":{size_mb},\
             \"streams\":{streams},\"chunk_kb\":{},\"verified\":{verified},\
             \"conn\":{stats}}}",
            chunk_size / 1024,
        ))
    });
    quic_revoke_session(session);
    out
}

fn clear_control(id: &str) {
    controls().lock().unwrap().remove(id);
}

/// Sessions the receiver has ACCEPTED over the TCP `prepare` step. The QUIC
/// receiver refuses to stage a file for a sessionId that was never authorized —
/// closing the "any host that reaches :58318 can inject a file" hole (Phase 0).
///
/// This is **consent enforcement, not cryptographic authentication**: the
/// sessionId travels in cleartext and is not secret, so a peer that genuinely did
/// a `prepare` could still send. A single-use, connection-bound token is the
/// stronger hardening step (§10.3 of the HTE plan). Dart keeps this set in lockstep
/// with its own accepted-session map (authorize on accept, revoke on teardown).
fn authorized_sessions() -> &'static Mutex<std::collections::HashSet<String>> {
    static A: OnceLock<Mutex<std::collections::HashSet<String>>> = OnceLock::new();
    A.get_or_init(|| Mutex::new(std::collections::HashSet::new()))
}

/// Authorize [session_id] for QUIC receipt — call when a `prepare` is accepted.
#[frb(sync)]
pub fn quic_authorize_session(session_id: String) {
    authorized_sessions().lock().unwrap().insert(session_id);
}

/// Revoke [session_id] — call when the session completes / is cancelled / removed.
#[frb(sync)]
pub fn quic_revoke_session(session_id: String) {
    authorized_sessions().lock().unwrap().remove(&session_id);
}

fn is_session_authorized(id: &str) -> bool {
    authorized_sessions().lock().unwrap().contains(id)
}

// ── Multi-stream receiver state (Phase 1b) ───────────────────────────────────

/// Chunk-completion bitmap. `set` returns false on a duplicate (a protocol
/// violation — QUIC streams are reliable, so a chunk can only arrive once).
#[frb(ignore)]
struct ChunkBitmap {
    bits: Vec<u64>,
    received: u64,
}

impl ChunkBitmap {
    fn new(total_chunks: u64) -> Self {
        Self {
            bits: vec![0u64; total_chunks.div_ceil(64) as usize],
            received: 0,
        }
    }

    /// Rebuild from ledger words (Phase 4 resume); `received` = popcount.
    fn from_bits(bits: Vec<u64>) -> Self {
        let received = bits.iter().map(|w| w.count_ones() as u64).sum();
        Self { bits, received }
    }

    fn set(&mut self, idx: u64) -> bool {
        let (word, bit) = ((idx / 64) as usize, idx % 64);
        if self.bits[word] & (1 << bit) != 0 {
            return false; // duplicate
        }
        self.bits[word] |= 1 << bit;
        self.received += 1;
        true
    }

    fn has(&self, idx: u64) -> bool {
        self.bits[(idx / 64) as usize] & (1 << (idx % 64)) != 0
    }

    /// Snapshot of the raw words (for the ledger and the have-bitmap on the wire).
    fn snapshot(&self) -> Vec<u64> {
        self.bits.clone()
    }
}

/// Shared per-file receive state: the control stream creates it; data streams
/// pwrite through it; the control stream awaits completion on `done`.
#[frb(ignore)]
struct RecvFileState {
    file_size: u64,
    chunk_size: u32,
    total_chunks: u64,
    /// Shared handle for positional writes (pwrite is offset-explicit, so
    /// concurrent data streams never race on a cursor).
    file: Arc<std::fs::File>,
    bitmap: Mutex<ChunkBitmap>,
    /// Per-chunk SHA-256 leaves (Phase 1d), indexed by chunk. Written once each
    /// by the data stream that receives that chunk; combined into a Merkle root
    /// on completion. ~32 B/chunk (3.2 MB for 100 GB @ 1 MB) — outside the pool.
    leaves: Mutex<Vec<[u8; 32]>>,
    bytes_received: std::sync::atomic::AtomicU64,
    failed: std::sync::atomic::AtomicBool,
    /// Notified on completion or failure; the control stream waits on this.
    done: tokio::sync::Notify,
    /// `.part` path (for ledger persistence + cleanup).
    part_path: String,
    /// Set when this transfer is resumable (V2): the stable key naming its ledger.
    resume_key: Option<String>,
}

impl RecvFileState {
    fn fail(&self) {
        self.failed.store(true, std::sync::atomic::Ordering::Relaxed);
        self.done.notify_waiters();
    }

    fn is_failed(&self) -> bool {
        self.failed.load(std::sync::atomic::Ordering::Relaxed)
    }

    fn is_complete(&self) -> bool {
        self.bitmap.lock().unwrap().received == self.total_chunks
    }

    /// Durably persist the resume ledger: fsync the `.part` DATA first, then
    /// write the current bitmap (strict ordering — the ledger never claims a
    /// chunk the disk lacks). No-op for non-resumable (V1) transfers. Runs the
    /// blocking fsync/write on the blocking pool.
    async fn persist_ledger(&self) {
        let Some(key) = self.resume_key.clone() else {
            return;
        };
        let file = self.file.clone();
        let bits = self.bitmap.lock().unwrap().snapshot();
        let (part, size, chunk_size, total) =
            (self.part_path.clone(), self.file_size, self.chunk_size, self.total_chunks);
        let _ = tokio::task::spawn_blocking(move || {
            if file.sync_data().is_ok() {
                let meta = crate::engine::resume::LedgerMeta {
                    size,
                    chunk_size,
                    total_chunks: total,
                    resume_key: &key,
                };
                let _ = crate::engine::resume::save(&part, &meta, &bits);
            }
        })
        .await;
    }
}

/// Resume keys with a live receive in progress — prevents two concurrent
/// transfers of the same stable key from fighting over one `.part`.
fn active_resume_keys() -> &'static Mutex<std::collections::HashSet<String>> {
    static A: OnceLock<Mutex<std::collections::HashSet<String>>> = OnceLock::new();
    A.get_or_init(|| Mutex::new(std::collections::HashSet::new()))
}

/// In-flight multi-stream receives, keyed by (sessionId, fileId). Control
/// streams insert; data streams look up (with a bounded wait — QUIC gives no
/// cross-stream ordering, so a data stream may be accepted first).
fn recv_files() -> &'static Mutex<HashMap<(String, String), Arc<RecvFileState>>> {
    static R: OnceLock<Mutex<HashMap<(String, String), Arc<RecvFileState>>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Wait (bounded) for the control stream to register the file's state.
async fn wait_for_state(
    key: &(String, String),
    timeout: std::time::Duration,
) -> Result<Arc<RecvFileState>, String> {
    let deadline = tokio::time::Instant::now() + timeout;
    loop {
        if let Some(s) = recv_files().lock().unwrap().get(key) {
            return Ok(s.clone());
        }
        if tokio::time::Instant::now() >= deadline {
            return Err(format!("no control stream for file {}", key.1));
        }
        tokio::time::sleep(std::time::Duration::from_millis(25)).await;
    }
}

/// A persistent client-side QUIC connection reused for every file in a session
/// (Phase 1a: connection reuse). Holds the `Endpoint` alongside the `Connection`
/// so both live as long as the session — dropping the endpoint would kill the
/// connection. `#[frb(ignore)]`: quinn types are not FFI-encodable and this is a
/// pure Rust-side impl detail (Dart drives it via quic_connect/send/disconnect).
#[frb(ignore)]
struct SessionConn {
    #[allow(dead_code)] // kept alive so the connection survives; dropped on disconnect
    endpoint: Endpoint,
    conn: quinn::Connection,
}

/// Persistent connections keyed by sessionId. Populated by [quic_connect], drained
/// by [quic_disconnect].
fn connections() -> &'static Mutex<HashMap<String, SessionConn>> {
    static C: OnceLock<Mutex<HashMap<String, SessionConn>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Establish ONE persistent QUIC connection to `host:port` for `session_id` — a
/// single QUIC/TLS handshake that every subsequent [quic_send_file] reuses
/// (`open_bi` per file). This is the fix for the per-file-handshake throughput
/// blocker. Idempotent: a re-connect replaces (and closes) any prior connection.
pub fn quic_connect(host: String, port: u16, session_id: String) -> Result<(), String> {
    runtime().block_on(async {
        let mut endpoint =
            tuned_client_endpoint(SocketAddr::new(Ipv6Addr::UNSPECIFIED.into(), 0))
                .map_err(|e| format!("client bind: {e}"))?;
        endpoint.set_default_client_config(client_config()?);

        let addr: SocketAddr = format!("{host}:{port}")
            .parse()
            .map_err(|_| format!("bad addr {host}:{port}"))?;
        let conn = endpoint
            .connect(addr, "bishare")
            .map_err(|e| format!("connect: {e}"))?
            .await
            .map_err(|e| format!("handshake: {e}"))?;

        let prev = connections()
            .lock()
            .unwrap()
            .insert(session_id, SessionConn { endpoint, conn });
        if let Some(old) = prev {
            old.conn.close(0u32.into(), b"replaced");
        }
        Ok(())
    })
}

/// Close and drop the persistent connection for `session_id` (call when the whole
/// session is done / cancelled / errored). Also clears the session's control state.
///
/// Teardown is paced in the background: after the close drains, the endpoint's
/// SOCKET is held open past the peer's keep-alive interval (5 s). If the single
/// CONNECTION_CLOSE datagram is lost (WiFi), the peer's next ping then hits the
/// still-open socket and gets a stateless reset — killing its connection
/// instantly. Dropping the socket immediately instead left the peer discovering
/// the death only via its 20 s per-read idle timeouts (observed on Android as
/// "idle timeout" ×streams, ~20 s after a sender cancel).
pub fn quic_disconnect(session_id: String) {
    let sc = connections().lock().unwrap().remove(&session_id);
    if let Some(sc) = sc {
        runtime().spawn(async move {
            sc.conn.close(0u32.into(), b"done");
            sc.endpoint.wait_idle().await;
            tokio::time::sleep(std::time::Duration::from_secs(11)).await;
            drop(sc); // now release the socket
        });
    }
    clear_control(&session_id);
}

/// Start a QUIC server on `[::]:port`, staging received files as `.part` files in
/// `save_dir`. Emits [QuicServerEvent]s to Dart; the first is `Ready` (or `Error`
/// on bind failure). Stop it with [quic_stop].
/// Delete abandoned resume partials (`.quic-r-*.part` + their `.rz`/`.rz.tmp`
/// ledgers) not modified in 7 days — a transfer never resumed would otherwise
/// leak its partial forever. In-progress resumes touch their files continuously,
/// so the 7-day floor never reaps a live one.
fn sweep_stale_resume_parts(save_dir: &str) {
    let Ok(entries) = std::fs::read_dir(save_dir) else {
        return;
    };
    let now = std::time::SystemTime::now();
    let max_age = std::time::Duration::from_secs(7 * 24 * 60 * 60);
    for e in entries.flatten() {
        let name = e.file_name();
        let name = name.to_string_lossy();
        let is_resume_artifact = name.starts_with(".quic-r-")
            && (name.ends_with(".part") || name.ends_with(".rz") || name.ends_with(".rz.tmp"));
        if !is_resume_artifact {
            continue;
        }
        let stale = e
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| now.duration_since(t).ok())
            .is_some_and(|age| age > max_age);
        if stale {
            let _ = std::fs::remove_file(e.path());
        }
    }
}

pub fn quic_serve(sink: StreamSink<QuicServerEvent>, port: u16, save_dir: String) {
    {
        let dir = save_dir.clone();
        runtime().spawn_blocking(move || sweep_stale_resume_parts(&dir));
    }
    let cfg = match server_config() {
        Ok(c) => c,
        Err(message) => {
            let _ = sink.add(QuicServerEvent::Error {
                message,
                session_id: None,
                file_id: None,
            });
            return;
        }
    };
    let addr = SocketAddr::new(Ipv6Addr::UNSPECIFIED.into(), port);
    let endpoint = match runtime().block_on(async { tuned_server_endpoint(cfg, addr) }) {
        Ok(ep) => ep,
        Err(e) => {
            let _ = sink.add(QuicServerEvent::Error {
                message: format!("bind {port}: {e}"),
                session_id: None,
                file_id: None,
            });
            return;
        }
    };
    servers().lock().unwrap().insert(port, endpoint.clone());
    runtime().spawn(async move {
        let _ = sink.add(QuicServerEvent::Ready);
        // Re-sweep at most hourly (not just at startup) so a long-lived desktop
        // process doesn't accumulate abandoned resume partials for its uptime.
        let mut last_sweep = tokio::time::Instant::now();
        while let Some(incoming) = endpoint.accept().await {
            if last_sweep.elapsed() >= std::time::Duration::from_secs(3600) {
                last_sweep = tokio::time::Instant::now();
                let dir = save_dir.clone();
                runtime().spawn_blocking(move || sweep_stale_resume_parts(&dir));
            }
            let sink = sink.clone();
            let dir = save_dir.clone();
            runtime().spawn(async move {
                if let Ok(conn) = incoming.await {
                    while let Ok((send, recv)) = conn.accept_bi().await {
                        let sink = sink.clone();
                        let dir = dir.clone();
                        runtime().spawn(async move {
                            match stream_dispatch(send, recv, &dir, Some(&sink), IDLE_TIMEOUT).await
                            {
                                Ok(Some(ev)) => {
                                    let _ = sink.add(ev);
                                }
                                Ok(None) => {} // data stream — the control stream emits
                                Err(f) => {
                                    let _ = sink.add(QuicServerEvent::Error {
                                        message: f.message,
                                        session_id: f.session_id,
                                        file_id: f.file_id,
                                    });
                                }
                            }
                        });
                    }
                }
            });
        }
    });
}

/// Stream exactly `size` bytes from `recv` into `file`, emitting a throttled
/// [QuicServerEvent::Progress] (~every [PROGRESS_EVERY] bytes) so the receiver UI
/// tracks the transfer live.
async fn drain_to_file(
    recv: &mut quinn::RecvStream,
    file: &mut tokio::fs::File,
    size: u64,
    sink: Option<&StreamSink<QuicServerEvent>>,
    session_id: &str,
    file_id: &str,
    file_name: &str,
    idle_timeout: std::time::Duration,
) -> Result<[u8; 32], String> {
    let mut remaining = size;
    let mut received: u64 = 0;
    let mut last_emit = tokio::time::Instant::now();
    // Phase 1d: streaming whole-file SHA-256 (in-order on the legacy path).
    let mut hasher = sha2::Sha256::default();
    // Pooled slab (held for the file's duration) — READ_CHUNK == SLAB_SIZE.
    // Bounded: a starved pool must fail this receive (cleaning its `.part`)
    // rather than park the task holding stream + file state forever.
    let mut buf = pool().acquire_timeout(idle_timeout).await?;
    let emit = |received: u64| {
        if let Some(sink) = sink {
            let _ = sink.add(QuicServerEvent::Progress {
                session_id: session_id.to_string(),
                file_id: file_id.to_string(),
                file_name: file_name.to_string(),
                received,
                total: size,
            });
        }
    };
    while remaining > 0 {
        let want = remaining.min(READ_CHUNK as u64) as usize;
        // Bound every read: a peer that stalls mid-body must not pin this task and
        // the `.part` forever (quinn keep-alive stops the connection idle-timer).
        let n = match tokio::time::timeout(idle_timeout, recv.read(&mut buf[..want])).await {
            Ok(r) => r
                .map_err(|e| e.to_string())?
                .ok_or_else(|| "stream ended early".to_string())?,
            Err(_) => return Err("receive idle timeout".to_string()),
        };
        sha2::Digest::update(&mut hasher, &buf[..n]);
        file.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
        remaining -= n as u64;
        received += n as u64;
        // Coalesce to ~30 Hz (was one event per 4 MB → ~225/s at 900 MB/s).
        if last_emit.elapsed() >= PROGRESS_INTERVAL {
            last_emit = tokio::time::Instant::now();
            emit(received);
        }
    }
    emit(received); // final 100% tick so the card lands on complete
    file.flush().await.map_err(|e| e.to_string())?;
    Ok(sha2::Digest::finalize(hasher).into())
}

/// Route one accepted stream by its first u32: a magic tag selects the
/// multi-stream control/data handlers; anything else is the legacy path's first
/// string length (≤ MAX_STR, so it can never collide with the magics). Returns
/// `Ok(None)` for data streams — their file's control stream emits the event.
async fn stream_dispatch(
    send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    save_dir: &str,
    sink: Option<&StreamSink<QuicServerEvent>>,
    idle_timeout: std::time::Duration,
) -> Result<Option<QuicServerEvent>, RecvFailure> {
    let first = idle(idle_timeout, async {
        recv.read_u32().await.map_err(|e| e.to_string())
    })
    .await?;
    match first {
        MAGIC_CONTROL => control_recv(send, recv, save_dir, sink, idle_timeout, false)
            .await
            .map(Some),
        MAGIC_CONTROL_V2 => control_recv(send, recv, save_dir, sink, idle_timeout, true)
            .await
            .map(Some),
        MAGIC_DATA => data_recv(recv, idle_timeout).await.map(|_| None),
        len => stream_recv(send, recv, save_dir, sink, idle_timeout, len as usize)
            .await
            .map(Some),
    }
}

/// Multi-stream control stream: header + geometry, pre-allocate the `.part`,
/// register the shared state, then wait for the data streams to complete —
/// emitting ~30 Hz progress and enforcing the stall guard (no progress for
/// `idle_timeout` ⇒ fail + cleanup). ACKs and returns the event on completion.
async fn control_recv(
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    save_dir: &str,
    sink: Option<&StreamSink<QuicServerEvent>>,
    idle_timeout: std::time::Duration,
    resume: bool,
) -> Result<QuicServerEvent, RecvFailure> {
    let session_id = idle(idle_timeout, read_str(&mut recv)).await?;

    // Same consent gate as the legacy path — before any disk state exists.
    if !is_session_authorized(&session_id) {
        return Err(format!("unauthorized session: {session_id}").into());
    }

    // From here the session is known — attach it to any failure so the UI can
    // clear the right progress card (e.g. sender-cancel mid-transfer).
    let sid = session_id.clone();
    let run = async move {
    let file_id = idle(idle_timeout, read_str(&mut recv)).await?;
    let sender_alias = idle(idle_timeout, read_str(&mut recv)).await?;
    let sender_fingerprint = idle(idle_timeout, read_str(&mut recv)).await?;
    let file_name = idle(idle_timeout, read_str(&mut recv)).await?;
    let file_type = idle(idle_timeout, read_str(&mut recv)).await?;
    let size = idle(idle_timeout, async {
        recv.read_u64().await.map_err(|e| e.to_string())
    })
    .await?;
    let chunk_size = idle(idle_timeout, async {
        recv.read_u32().await.map_err(|e| e.to_string())
    })
    .await?;
    let stream_count = idle(idle_timeout, async {
        recv.read_u8().await.map_err(|e| e.to_string())
    })
    .await?;
    // V2 (resume) header carries a trailing stable resume key.
    let resume_key = if resume {
        Some(idle(idle_timeout, read_str(&mut recv)).await?)
    } else {
        None
    };

    // Geometry sanity — these come off the network.
    if !(MIN_CHUNK..=MAX_CHUNK).contains(&chunk_size) {
        return Err(format!("bad chunk size {chunk_size}"));
    }
    if stream_count == 0 || stream_count > MAX_STREAMS {
        return Err(format!("bad stream count {stream_count}"));
    }
    if size == 0 {
        return Err("zero-size file over multi-stream".to_string());
    }
    let total_chunks = size.div_ceil(chunk_size as u64);

    tokio::fs::create_dir_all(save_dir).await.map_err(|e| e.to_string())?;
    // Resume (V2) → stable resume-key-scoped name so a reconnect finds its
    // partial; otherwise session-scoped so concurrent same-fileId transfers
    // don't collide.
    let temp_path = match &resume_key {
        Some(k) => format!("{save_dir}/{}", resume_part_name(k)),
        None => format!("{save_dir}/{}", part_name(&session_id, &file_id)),
    };

    // Guard: reject a second live receive for the same stable key (resume) or the
    // same (session,file) (fresh) so two streams can't fight over one `.part`.
    let _key_guard = if let Some(k) = &resume_key {
        if !active_resume_keys().lock().unwrap().insert(k.clone()) {
            return Err(format!("resume key already active for {file_id}"));
        }
        ActiveKeyGuard(Some(k.clone()))
    } else {
        ActiveKeyGuard(None)
    };
    let key = (session_id.clone(), file_id.clone());
    if recv_files().lock().unwrap().contains_key(&key) {
        return Err(format!("duplicate control stream for file {file_id}"));
    }

    // Open the `.part`: resume from an existing ledger if one matches, else
    // create + pre-allocate a fresh sparse file.
    let ledger_meta = crate::engine::resume::LedgerMeta {
        size,
        chunk_size,
        total_chunks,
        resume_key: resume_key.as_deref().unwrap_or(""),
    };
    let loaded = resume_key
        .as_ref()
        .and_then(|_| crate::engine::resume::load(&temp_path, &ledger_meta));
    let (file, resumed_bits) = {
        let path = temp_path.clone();
        let has_ledger = loaded.is_some();
        let f = tokio::task::spawn_blocking(move || -> std::io::Result<std::fs::File> {
            if has_ledger {
                // Resume: open the EXISTING partial (do NOT truncate).
                std::fs::OpenOptions::new().read(true).write(true).open(&path)
            } else {
                let f = std::fs::File::create(&path)?;
                f.set_len(size)?;
                Ok(f)
            }
        })
        .await
        .map_err(|e| e.to_string())?;
        // A ledger without a readable/right-sized `.part` → fall back to fresh.
        match f {
            Ok(f) if loaded.is_some() && f.metadata().map(|m| m.len()).unwrap_or(0) == size => {
                (f, loaded)
            }
            Ok(f) if loaded.is_some() => {
                // Partial gone/mismatched — recreate fresh.
                f.set_len(size).map_err(|e| e.to_string())?;
                crate::engine::resume::remove(&temp_path);
                (f, None)
            }
            Ok(f) => (f, None),
            Err(_) if loaded.is_some() => {
                // Ledger present but partial unreadable → fresh.
                crate::engine::resume::remove(&temp_path);
                let path = temp_path.clone();
                let f = tokio::task::spawn_blocking(move || -> std::io::Result<std::fs::File> {
                    let f = std::fs::File::create(&path)?;
                    f.set_len(size)?;
                    Ok(f)
                })
                .await
                .map_err(|e| e.to_string())?
                .map_err(|e| e.to_string())?;
                (f, None)
            }
            Err(e) => return Err(e.to_string()),
        }
    };

    let bitmap = match &resumed_bits {
        Some(bits) => ChunkBitmap::from_bits(bits.clone()),
        None => ChunkBitmap::new(total_chunks),
    };
    let already = bitmap.received;
    let state = Arc::new(RecvFileState {
        file_size: size,
        chunk_size,
        total_chunks,
        file: Arc::new(file),
        bitmap: Mutex::new(bitmap),
        leaves: Mutex::new(vec![[0u8; 32]; total_chunks as usize]),
        bytes_received: std::sync::atomic::AtomicU64::new(0),
        failed: std::sync::atomic::AtomicBool::new(false),
        done: tokio::sync::Notify::new(),
        part_path: temp_path.clone(),
        resume_key: resume_key.clone(),
    });
    recv_files().lock().unwrap().insert(key.clone(), state.clone());

    // Resume handshake: tell the sender which chunks we already have so it sends
    // only the gaps. `[u64 already_bytes][u64 num_words][words: u64 BE...]`.
    // This is written BEFORE re-hashing so a large partial's disk re-hash (which
    // can take longer than the sender's idle timeout) never stalls the sender.
    if resume_key.is_some() {
        let words = state.bitmap.lock().unwrap().snapshot();
        let already_bytes = already.saturating_mul(chunk_size as u64).min(size);
        let mut buf = Vec::with_capacity(16 + words.len() * 8);
        buf.extend_from_slice(&already_bytes.to_be_bytes());
        buf.extend_from_slice(&(words.len() as u64).to_be_bytes());
        for w in &words {
            buf.extend_from_slice(&w.to_be_bytes());
        }
        send.write_all(&buf).await.map_err(|e| e.to_string())?;
    }

    // Resume: rebuild the leaves of the chunks already on disk (their hashes were
    // lost with the old RAM state) so the final Merkle root is complete. Done
    // BEFORE control_wait so all have-leaves exist by the time completion (which
    // could arrive concurrently as gaps land) is observed.
    if already > 0 {
        if let Err(e) = rehash_have_chunks(&state).await {
            recv_files().lock().unwrap().remove(&key);
            state.fail(); // wake any data streams already receiving gaps
            let _ = tokio::fs::remove_file(&temp_path).await;
            crate::engine::resume::remove(&temp_path);
            return Err(e);
        }
    }

    // Wait for the data streams. On failure: if this is a resumable transfer,
    // PERSIST the ledger + KEEP the partial so it can continue later; otherwise
    // (v1) drop the partial as before.
    let waited = control_wait(
        &state,
        sink,
        &session_id,
        &file_id,
        &file_name,
        idle_timeout,
    )
    .await;
    if let Err(e) = waited {
        recv_files().lock().unwrap().remove(&key);
        if resume_key.is_some() {
            state.persist_ledger().await; // keep progress for next time
        } else {
            let _ = tokio::fs::remove_file(&temp_path).await;
        }
        return Err(e);
    }

    // Phase 1d: read + verify the 32-byte Merkle-root trailer. ANY failure drops
    // the full-size `.part` AND its ledger (a completed-but-unverified file, or a
    // content mismatch after resume, must not be left behind or resumed).
    let trailer = idle(idle_timeout, read_trailer(&mut recv)).await;
    recv_files().lock().unwrap().remove(&key);
    let discard = |path: &str| {
        let path = path.to_string();
        crate::engine::resume::remove(&path);
        async move {
            let _ = tokio::fs::remove_file(&path).await;
        }
    };
    // The data is COMPLETE on disk here (control_wait returned Ok). Distinguish
    // a genuine content problem (Merkle MISMATCH → delete + restart clean) from a
    // TRANSIENT failure at the tail (trailer read / ACK stall or drop). For a
    // resumable transfer a transient tail failure must KEEP the near-complete
    // partial + persist its ledger — otherwise a stall 32 bytes from the end
    // forces re-transferring the whole (multi-GB) file, the exact case resume
    // exists to prevent (review finding: transient-tail-delete).
    let resumable = resume_key.is_some();
    let verified = match trailer {
        Ok(Some(sender_root)) => {
            let our_root = merkle_root(&state.leaves.lock().unwrap());
            if our_root != sender_root {
                // Real content corruption — never resume a bad partial.
                discard(&temp_path).await;
                return Err("integrity check failed (merkle root mismatch)".to_string());
            }
            true
        }
        Ok(None) => {
            if resumable {
                state.persist_ledger().await;
            } else {
                discard(&temp_path).await;
            }
            return Err("integrity trailer missing (kept for resume)".to_string());
        }
        Err(e) => {
            if resumable {
                state.persist_ledger().await;
            } else {
                discard(&temp_path).await;
            }
            return Err(e);
        }
    };

    // Complete + VERIFIED. ACK FIRST, then remove the ledger — so a transient
    // ACK-write failure keeps the resumable partial instead of forcing a full
    // re-transfer (review finding: ACK-write-delete).
    if let Err(e) = send.write_all(&[1u8]).await.map_err(|e| e.to_string()) {
        if resumable {
            state.persist_ledger().await;
        } else {
            discard(&temp_path).await;
        }
        return Err(e);
    }
    let _ = send.finish();
    crate::engine::resume::remove(&temp_path); // verified + ACKed → ledger done

    Ok(QuicServerEvent::Received {
        session_id,
        file_id,
        sender_alias,
        sender_fingerprint,
        file_name,
        file_type,
        temp_path,
        size,
        verified,
    })
    };
    with_ctx(run.await, &sid, None)
}

/// Completion wait-loop for one multi-stream file: wakes on chunk arrival (or
/// every PROGRESS_INTERVAL), emits coalesced progress, and fails if no byte
/// arrives for `idle_timeout` (the Phase 0 stall guard, at file granularity).
async fn control_wait(
    state: &RecvFileState,
    sink: Option<&StreamSink<QuicServerEvent>>,
    session_id: &str,
    file_id: &str,
    file_name: &str,
    idle_timeout: std::time::Duration,
) -> Result<(), String> {
    // Bytes already on disk from a previous (resumed) session — progress is this
    // base plus the newly-received gap bytes, and completion is bitmap-driven so
    // it accounts for the resumed chunks too.
    let base = {
        let bm = state.bitmap.lock().unwrap();
        (bm.received.saturating_mul(state.chunk_size as u64)).min(state.file_size)
    };
    let emit = |received: u64| {
        if let Some(sink) = sink {
            let _ = sink.add(QuicServerEvent::Progress {
                session_id: session_id.to_string(),
                file_id: file_id.to_string(),
                file_name: file_name.to_string(),
                received: (base + received).min(state.file_size),
                total: state.file_size,
            });
        }
    };
    emit(0); // show the resumed baseline immediately
    let mut last_bytes = 0u64;
    let mut last_activity = tokio::time::Instant::now();
    let mut last_ledger = tokio::time::Instant::now();
    // NOTE: we do NOT read the control stream here — after completion it carries
    // the 32-byte Merkle-root trailer (read by control_recv). A mid-transfer
    // sender abort resets the DATA streams, which data_recv turns into
    // state.fail() → this loop returns promptly; an abort BEFORE any data
    // preamble is caught by the idle_timeout below.
    loop {
        if state.is_failed() {
            return Err("a data stream failed".to_string());
        }
        if state.is_complete() {
            emit(state.file_size);
            return Ok(());
        }
        let bytes = state.bytes_received.load(std::sync::atomic::Ordering::Relaxed);
        if bytes > last_bytes {
            last_bytes = bytes;
            last_activity = tokio::time::Instant::now();
            emit(bytes);
        } else if last_activity.elapsed() >= idle_timeout {
            state.fail(); // poison so in-flight data streams bail out too
            return Err("receive idle timeout".to_string());
        }
        // Persist the resume ledger at most ~1 Hz (fsync is not free) so a crash
        // loses at most ~1 s of received chunks.
        if last_ledger.elapsed() >= std::time::Duration::from_secs(1) {
            last_ledger = tokio::time::Instant::now();
            state.persist_ledger().await;
        }
        tokio::select! {
            _ = state.done.notified() => {}
            _ = tokio::time::sleep(PROGRESS_INTERVAL) => {}
        }
    }
}

/// Read the 32-byte integrity trailer (Phase 1d), or `None` if the stream FINs
/// cleanly with NO trailer at all — a pre-1d sender that never sends one. A
/// partial trailer (1..31 bytes then FIN) is a truncation error. This lets a new
/// receiver stay interoperable with an old sender (accept the file as unverified)
/// while still detecting truncation.
async fn read_trailer(recv: &mut quinn::RecvStream) -> Result<Option<[u8; 32]>, String> {
    let mut buf = [0u8; 32];
    let mut filled = 0;
    while filled < 32 {
        match recv.read(&mut buf[filled..]).await.map_err(|e| e.to_string())? {
            None if filled == 0 => return Ok(None), // clean FIN, no trailer (old sender)
            None => return Err("truncated integrity trailer".to_string()),
            Some(n) => filled += n,
        }
    }
    Ok(Some(buf))
}

/// Read the next frame's 8-byte offset, or `None` on a clean FIN at a frame
/// boundary (how a data stream signals "no more chunks").
async fn read_frame_offset(recv: &mut quinn::RecvStream) -> Result<Option<u64>, String> {
    let mut buf = [0u8; 8];
    let mut filled = 0;
    while filled < 8 {
        match recv.read(&mut buf[filled..]).await.map_err(|e| e.to_string())? {
            None if filled == 0 => return Ok(None),
            None => return Err("truncated frame header".to_string()),
            Some(n) => filled += n,
        }
    }
    Ok(Some(u64::from_be_bytes(buf)))
}

/// Multi-stream data stream: `[str sessionId][str fileId]` then offset-framed
/// chunks, each validated (geometry + CRC32C + duplicate) and pwritten in place.
/// The CRC is a storage/pipeline-bug assertion — QUIC AEAD already guarantees
/// wire integrity — so a mismatch fails the file, never "re-requests".
async fn data_recv(
    mut recv: quinn::RecvStream,
    idle_timeout: std::time::Duration,
) -> Result<(), RecvFailure> {
    let session_id = idle(idle_timeout, read_str(&mut recv)).await?;
    let file_id = idle(idle_timeout, read_str(&mut recv)).await?;
    // The control stream may not have set up the state yet (QUIC has no
    // cross-stream ordering); wait briefly for it. Its presence also implies the
    // session passed the consent gate (control_recv enforces it).
    let key = (session_id.clone(), file_id.clone());
    let state = with_ctx(
        wait_for_state(&key, idle_timeout.min(std::time::Duration::from_secs(5))).await,
        &session_id,
        Some(&file_id),
    )?;

    let run = async {
        loop {
            if state.is_failed() {
                return Err("file already failed".to_string());
            }
            let abs_offset = match idle(idle_timeout, read_frame_offset(&mut recv)).await? {
                Some(v) => v,
                None => return Ok(()), // clean FIN — this stream is done
            };
            let payload_len = idle(idle_timeout, async {
                recv.read_u32().await.map_err(|e| e.to_string())
            })
            .await?;
            let crc = idle(idle_timeout, async {
                recv.read_u32().await.map_err(|e| e.to_string())
            })
            .await?;
            let _flags = idle(idle_timeout, async {
                recv.read_u8().await.map_err(|e| e.to_string())
            })
            .await?;

            let idx = validate_chunk(abs_offset, payload_len, state.chunk_size, state.file_size)?;

            // Pooled slab per chunk — the suspension is the §5 backpressure that
            // bounds receiver RAM, but bounded so a starved pool fails this
            // stream (waking control_wait) instead of leaving a zombie task
            // holding the RecvStream. validate_chunk guarantees
            // payload_len ≤ chunk_size ≤ SLAB_SIZE.
            let len = payload_len as usize;
            let mut slab = pool().acquire_timeout(idle_timeout).await?;
            if state.is_failed() {
                return Err("file already failed".to_string());
            }
            idle(idle_timeout, async {
                recv.read_exact(&mut slab[..len]).await.map_err(|e| e.to_string())
            })
            .await?;

            if crc32c::crc32c(&slab[..len]) != crc {
                return Err(format!("crc mismatch on chunk {idx} (disk/pipeline assert)"));
            }

            // Merkle leaf (Phase 1d whole-file integrity) — hash the chunk before
            // the slab moves into the writer.
            let leaf = sha256_leaf(&slab[..len]);

            // Positional write on the blocking pool (page-cache flushes must not
            // stall the async reactor). The slab moves in and returns to the pool
            // when the closure drops it.
            let file = state.file.clone();
            tokio::task::spawn_blocking(move || write_all_at(&file, &slab[..len], abs_offset))
                .await
                .map_err(|e| e.to_string())?
                .map_err(|e| e.to_string())?;

            state.leaves.lock().unwrap()[idx as usize] = leaf;
            if !state.bitmap.lock().unwrap().set(idx) {
                return Err(format!("duplicate chunk {idx}"));
            }
            state
                .bytes_received
                .fetch_add(payload_len as u64, std::sync::atomic::Ordering::Relaxed);
            if state.is_complete() {
                state.done.notify_waiters();
            }
        }
    };
    let out: Result<(), String> = run.await;
    if out.is_err() {
        state.fail(); // wake the control stream so the file aborts promptly
    }
    with_ctx(out, &session_id, Some(&file_id))
}

/// Core receive: parse the header, stream the body into `save_dir/.quic-<fileId>.part`,
/// ACK one byte. Returns the [QuicServerEvent::Received] to emit. StreamSink-free.
/// `first_len` is the sessionId string length already consumed by [stream_dispatch].
async fn stream_recv(
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    save_dir: &str,
    sink: Option<&StreamSink<QuicServerEvent>>,
    idle_timeout: std::time::Duration,
    first_len: usize,
) -> Result<QuicServerEvent, RecvFailure> {
    // Bound every header read too — a peer that opens a stream and sends nothing
    // (or a partial header) must time out instead of pinning the task forever.
    let session_id = idle(idle_timeout, read_str_body(&mut recv, first_len)).await?;

    // Consent gate (Phase 0): refuse to stage a file for a session the receiver
    // never accepted over TCP `prepare`. Rejected BEFORE any `.part` is created,
    // so an unsolicited host on :58318 cannot write to disk or consume the save dir.
    if !is_session_authorized(&session_id) {
        return Err(format!("unauthorized session: {session_id}").into());
    }

    // From here the session is known — attach it to failures so the UI can clear
    // the right progress card (e.g. sender-cancel resets the stream mid-body).
    let sid = session_id.clone();
    let run = async move {
    let file_id = idle(idle_timeout, read_str(&mut recv)).await?;
    let sender_alias = idle(idle_timeout, read_str(&mut recv)).await?;
    let sender_fingerprint = idle(idle_timeout, read_str(&mut recv)).await?;
    let file_name = idle(idle_timeout, read_str(&mut recv)).await?;
    let file_type = idle(idle_timeout, read_str(&mut recv)).await?;
    let size = idle(idle_timeout, async {
        recv.read_u64().await.map_err(|e| e.to_string())
    })
    .await?;

    tokio::fs::create_dir_all(save_dir).await.map_err(|e| e.to_string())?;
    let temp_path = format!("{save_dir}/{}", part_name(&session_id, &file_id));
    let mut file = tokio::fs::File::create(&temp_path).await.map_err(|e| e.to_string())?;

    // On cancel/error/idle-timeout the sender resets the stream (or never finishes)
    // — drop the partial `.part` so a cancelled/stalled transfer leaves nothing.
    let our_hash = match drain_to_file(
        &mut recv, &mut file, size, sink, &session_id, &file_id, &file_name, idle_timeout,
    )
    .await
    {
        Ok(h) => h,
        Err(e) => {
            drop(file);
            let _ = tokio::fs::remove_file(&temp_path).await;
            return Err(e);
        }
    };

    // Phase 1d: verify the whole-file SHA-256 trailer the sender sends after the
    // body against our streaming digest. The LEGACY path is NOT version-gated
    // (unlike multi-stream), so a pre-1d sender sends no trailer and FINs after
    // the body — accept that as unverified rather than failing (keeps OLD→NEW
    // QUIC working during a mixed-version rollout). A truncated/wrong trailer is
    // still a hard failure.
    let verified = match idle(idle_timeout, read_trailer(&mut recv)).await {
        Ok(Some(sender_hash)) => {
            if our_hash != sender_hash {
                drop(file);
                let _ = tokio::fs::remove_file(&temp_path).await;
                return Err("integrity check failed (sha256 mismatch)".to_string());
            }
            true
        }
        Ok(None) => false, // pre-1d sender: no trailer → accept, unverified
        Err(e) => {
            drop(file);
            let _ = tokio::fs::remove_file(&temp_path).await;
            return Err(e);
        }
    };

    // File complete + verified — but if the ACK write fails the sender re-sends
    // (→ TCP), so drop this `.part` rather than orphan a full file Dart never
    // finalises.
    if let Err(e) = send.write_all(&[1u8]).await.map_err(|e| e.to_string()) {
        drop(file);
        let _ = tokio::fs::remove_file(&temp_path).await;
        return Err(e);
    }
    let _ = send.finish();

    Ok(QuicServerEvent::Received {
        session_id,
        file_id,
        sender_alias,
        sender_fingerprint,
        file_name,
        file_type,
        temp_path,
        size,
        verified,
    })
    };
    with_ctx(run.await, &sid, None)
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Send one file over the persistent QUIC connection established by [quic_connect]
/// for this `session_id` — NO per-file handshake (Phase 1a). `streams` > 1 selects
/// the offset-framed multi-stream format (Phase 1b) and must only be passed when
/// the receiver advertised `streamsPerFile` in its PrepareResponse; `streams` ≤ 1
/// sends the byte-identical legacy single-stream body. Reports bytes-sent
/// progress; the receiver ACKs on completion. Any error propagates so the caller
/// can fall back to TCP. The connection is NOT closed here — it is reused for the
/// next file and torn down by [quic_disconnect] at session end.
/// NOTE on error delivery: FRB drops the return value of a function that also
/// takes a `StreamSink` (the generated Dart `unawaited()`s it — an `Err` there
/// surfaces as an UNHANDLED zone exception and never reaches the progress
/// stream, so Dart's `await for` would hang and the TCP fallback never fire).
/// Errors are therefore delivered INTO the sink via `add_error`, which makes
/// the Dart stream throw — exactly what the caller's try/catch expects.
#[allow(clippy::too_many_arguments)]
pub fn quic_send_file(
    sink: StreamSink<u64>,
    session_id: String,
    file_id: String,
    sender_alias: String,
    sender_fingerprint: String,
    file_path: String,
    file_name: String,
    file_type: String,
    streams: u8,
    chunk_size: u32,
    resume: bool,
) {
    let result = quic_send_file_inner(
        &sink,
        &session_id,
        &file_id,
        &sender_alias,
        &sender_fingerprint,
        &file_path,
        &file_name,
        &file_type,
        streams,
        chunk_size,
        resume,
    );
    if let Err(e) = result {
        // Deliver the failure into the progress stream (→ Dart await-for throws
        // → caller falls back to TCP). If even that fails, there is nothing
        // more we can do — the sink is torn down.
        let _ = sink.add_error(e);
    }
}

/// Deterministic resume key — stable across reconnects (same sender + file name
/// + size → same key → same `.part`), no sender-side persistence needed. Only a
/// same-name-same-size DIFFERENT file collides, which the final Merkle verify
/// catches (fails closed → clean restart).
fn derive_resume_key(fp: &str, name: &str, size: u64) -> String {
    let mut h = sha2::Sha256::default();
    sha2::Digest::update(&mut h, fp.as_bytes());
    sha2::Digest::update(&mut h, [0u8]);
    sha2::Digest::update(&mut h, name.as_bytes());
    sha2::Digest::update(&mut h, [0u8]);
    sha2::Digest::update(&mut h, size.to_be_bytes());
    let d: [u8; 32] = sha2::Digest::finalize(h).into();
    d.iter().map(|b| format!("{b:02x}")).collect()
}

#[allow(clippy::too_many_arguments)]
fn quic_send_file_inner(
    sink: &StreamSink<u64>,
    session_id: &str,
    file_id: &str,
    sender_alias: &str,
    sender_fingerprint: &str,
    file_path: &str,
    file_name: &str,
    file_type: &str,
    streams: u8,
    chunk_size: u32,
    resume: bool,
) -> Result<u64, String> {
    // Reuse the session's connection (cheap Arc clone) — established once by
    // quic_connect. `open_bi` on a live connection is handshake-free.
    let conn = connections()
        .lock()
        .unwrap()
        .get(session_id)
        .map(|sc| sc.conn.clone())
        .ok_or_else(|| format!("no QUIC connection for session {session_id}"))?;
    // Control state keyed by session; quic_cancel targets the same key, so a
    // cancel aborts whichever file is currently streaming.
    let control = control_for(session_id);
    let streams = streams.min(MAX_STREAMS);
    let chunk_size = chunk_size.clamp(MIN_CHUNK, MAX_CHUNK);
    runtime().block_on(async {
        if streams > 1 {
            // Resume (V2) only on the multi-stream path and only when the receiver
            // advertised support; the key is derived from stable inputs.
            let resume_key = if resume {
                let size = tokio::fs::metadata(file_path)
                    .await
                    .map(|m| m.len())
                    .unwrap_or(0);
                Some(derive_resume_key(sender_fingerprint, file_name, size))
            } else {
                None
            };
            return stream_send_multi(
                &conn,
                &control,
                session_id,
                file_id,
                sender_alias,
                sender_fingerprint,
                file_path,
                file_name,
                file_type,
                streams,
                chunk_size,
                resume_key.as_deref(),
                |n| {
                    let _ = sink.add(n);
                },
            )
            .await;
        }
        let (send, recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
        stream_send(
            send,
            recv,
            &control,
            session_id,
            file_id,
            sender_alias,
            sender_fingerprint,
            file_path,
            file_name,
            file_type,
            |n| {
                let _ = sink.add(n);
            },
        )
        .await
    })
}

/// Core send: write header + body on a bi stream, report progress, await the ACK.
#[allow(clippy::too_many_arguments)]
async fn stream_send(
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    control: &ControlState,
    session_id: &str,
    file_id: &str,
    sender_alias: &str,
    sender_fingerprint: &str,
    file_path: &str,
    file_name: &str,
    file_type: &str,
    mut on_progress: impl FnMut(u64),
) -> Result<u64, String> {
    // Acquire the slab BEFORE writing the header: once the header is on the
    // wire the receiver's per-read idle clock is running, so parking in a
    // starved pool here would make a perfectly healthy peer time out and delete
    // its `.part`. Bounded, so starvation fails cleanly instead of pinning us.
    let mut buf = pool().acquire_timeout(IDLE_TIMEOUT).await?;

    write_str(&mut send, session_id).await?;
    write_str(&mut send, file_id).await?;
    write_str(&mut send, sender_alias).await?;
    write_str(&mut send, sender_fingerprint).await?;
    write_str(&mut send, file_name).await?;
    write_str(&mut send, file_type).await?;
    let meta = tokio::fs::metadata(file_path).await.map_err(|e| e.to_string())?;
    let size = meta.len();
    send.write_u64(size).await.map_err(|e| e.to_string())?;

    let mut file = tokio::fs::File::open(file_path).await.map_err(|e| e.to_string())?;
    let mut sent = 0u64;
    let mut last_emit = tokio::time::Instant::now();
    // Phase 1d: streaming whole-file SHA-256 (legacy S=1 is in-order, so a plain
    // running digest works — no Merkle needed).
    let mut hasher = sha2::Sha256::default();
    loop {
        // Abort mid-stream on cancel — reset() makes the receiver's read fail so it
        // discards the partial `.part` instead of finalising it.
        if control.has(ControlState::CANCELLED) {
            let _ = send.reset(2u32.into());
            return Err("cancelled".to_string());
        }
        let n = file.read(&mut buf).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        sha2::Digest::update(&mut hasher, &buf[..n]);
        write_all_bounded(&mut send, &buf[..n]).await?;
        sent += n as u64;
        // Coalesce to ~30 Hz instead of one event per 1 MB (~900/s at 900 MB/s).
        if last_emit.elapsed() >= PROGRESS_INTERVAL {
            last_emit = tokio::time::Instant::now();
            on_progress(sent);
        }
    }
    on_progress(sent); // final tick so Dart lands on 100%
    // Whole-file hash trailer (Phase 1d), then finish + await ACK.
    let digest: [u8; 32] = sha2::Digest::finalize(hasher).into();
    write_all_bounded(&mut send, &digest).await?;
    send.finish().map_err(|e| e.to_string())?;

    // Bound the ACK wait — if the receiver stalls after we finish, keep-alive keeps
    // the connection alive so read_exact would otherwise block indefinitely.
    let mut ack = [0u8; 1];
    match tokio::time::timeout(IDLE_TIMEOUT, recv.read_exact(&mut ack)).await {
        Ok(r) => r.map_err(|e| e.to_string())?,
        Err(_) => return Err("ack read idle timeout".to_string()),
    };
    Ok(sent)
}

/// Multi-stream send (Phase 1b): a control stream carries the header + geometry,
/// then S data streams pull chunk indices from a shared AtomicU64 dispatcher
/// (natural load balancing) and send offset-framed chunks. Progress is pumped at
/// ~30 Hz from a shared byte counter; the ACK is awaited on the control stream.
#[allow(clippy::too_many_arguments)]
async fn stream_send_multi(
    conn: &quinn::Connection,
    control: &Arc<ControlState>,
    session_id: &str,
    file_id: &str,
    sender_alias: &str,
    sender_fingerprint: &str,
    file_path: &str,
    file_name: &str,
    file_type: &str,
    streams: u8,
    chunk_size: u32,
    resume_key: Option<&str>,
    mut on_progress: impl FnMut(u64),
) -> Result<u64, String> {
    let meta = tokio::fs::metadata(file_path).await.map_err(|e| e.to_string())?;
    let size = meta.len();
    if size == 0 {
        return Err("zero-size file over multi-stream".to_string());
    }
    let total_chunks = size.div_ceil(chunk_size as u64);
    // Never open more streams than there are chunks to carry.
    let effective = (streams as u64).min(total_chunks).max(1) as u8;

    // Control stream first: header + geometry, held open for the final ACK.
    let (mut csend, mut crecv) = conn.open_bi().await.map_err(|e| e.to_string())?;
    let magic = if resume_key.is_some() { MAGIC_CONTROL_V2 } else { MAGIC_CONTROL };
    csend.write_u32(magic).await.map_err(|e| e.to_string())?;
    write_str(&mut csend, session_id).await?;
    write_str(&mut csend, file_id).await?;
    write_str(&mut csend, sender_alias).await?;
    write_str(&mut csend, sender_fingerprint).await?;
    write_str(&mut csend, file_name).await?;
    write_str(&mut csend, file_type).await?;
    csend.write_u64(size).await.map_err(|e| e.to_string())?;
    csend.write_u32(chunk_size).await.map_err(|e| e.to_string())?;
    csend.write_u8(effective).await.map_err(|e| e.to_string())?;
    if let Some(k) = resume_key {
        write_str(&mut csend, k).await?;
    }

    // Resume (V2): read back the receiver's have-bitmap so we skip chunks it
    // already holds. `[u64 already_bytes][u64 num_words][words: u64 BE...]`.
    let num_words = total_chunks.div_ceil(64) as usize;
    let mut have = vec![0u64; num_words];
    let mut already_bytes = 0u64;
    if resume_key.is_some() {
        let mut hdr = [0u8; 16];
        idle(IDLE_TIMEOUT, async {
            crecv.read_exact(&mut hdr).await.map_err(|e| e.to_string())
        })
        .await?;
        already_bytes = u64::from_be_bytes(hdr[..8].try_into().unwrap());
        let words = u64::from_be_bytes(hdr[8..].try_into().unwrap()) as usize;
        if words != num_words {
            return Err(format!("resume bitmap size mismatch: {words} vs {num_words}"));
        }
        let mut wbuf = vec![0u8; words * 8];
        idle(IDLE_TIMEOUT, async {
            crecv.read_exact(&mut wbuf).await.map_err(|e| e.to_string())
        })
        .await?;
        for (i, w) in wbuf.chunks_exact(8).enumerate() {
            have[i] = u64::from_be_bytes(w.try_into().unwrap());
        }
    }
    let have = Arc::new(have);

    // One shared read handle (pread is offset-explicit) + the chunk dispatcher.
    let file = Arc::new(std::fs::File::open(file_path).map_err(|e| e.to_string())?);
    let dispatcher = Arc::new(std::sync::atomic::AtomicU64::new(0));
    // Progress starts at the already-received bytes (resume) so the bar reflects
    // true completion; gap sends add to it.
    let sent_bytes = Arc::new(std::sync::atomic::AtomicU64::new(already_bytes.min(size)));
    // Per-chunk SHA-256 leaves, filled as each stream reads its chunks (Phase
    // 1d) — no extra file pass. One writer per index (dispatcher is unique).
    let leaves = Arc::new(Mutex::new(vec![[0u8; 32]; total_chunks as usize]));

    let mut tasks = tokio::task::JoinSet::new();
    for _ in 0..effective {
        let conn = conn.clone();
        let control = control.clone();
        let file = file.clone();
        let dispatcher = dispatcher.clone();
        let sent_bytes = sent_bytes.clone();
        let leaves = leaves.clone();
        let have = have.clone();
        let (session_id, file_id) = (session_id.to_string(), file_id.to_string());
        tasks.spawn(async move {
            data_send_task(
                conn, control, file, dispatcher, sent_bytes, leaves, have, size, chunk_size,
                total_chunks, &session_id, &file_id,
            )
            .await
        });
    }

    // Pump coalesced progress while joining the data tasks; first error wins and
    // aborts the rest (their streams reset → the receiver poisons the file).
    let mut result: Result<(), String> = Ok(());
    let mut ticker = tokio::time::interval(PROGRESS_INTERVAL);
    loop {
        tokio::select! {
            _ = ticker.tick() => {
                on_progress(sent_bytes.load(std::sync::atomic::Ordering::Relaxed));
            }
            joined = tasks.join_next() => match joined {
                None => break,
                Some(Ok(Ok(()))) => {}
                Some(Ok(Err(e))) => {
                    if result.is_ok() {
                        result = Err(e);
                        tasks.abort_all();
                    }
                }
                Some(Err(e)) => {
                    if !e.is_cancelled() && result.is_ok() {
                        result = Err(format!("send task panicked: {e}"));
                        tasks.abort_all();
                    }
                }
            }
        }
    }
    result?;
    on_progress(size); // final tick so Dart lands on 100%

    // Phase 1d: all chunks sent + hashed — write the Merkle-root trailer on the
    // control stream so the receiver can verify, then finish and await the ACK.
    let root = merkle_root(&leaves.lock().unwrap());
    write_all_bounded(&mut csend, &root).await?;
    csend.finish().map_err(|e| e.to_string())?;
    let mut ack = [0u8; 1];
    match tokio::time::timeout(IDLE_TIMEOUT, crecv.read_exact(&mut ack)).await {
        Ok(r) => r.map_err(|e| e.to_string())?,
        Err(_) => return Err("ack read idle timeout".to_string()),
    };
    Ok(size)
}

/// One sender data stream: pulls the next chunk index from the dispatcher,
/// preads it on the blocking pool, frames it (offset/len/crc32c/flags), writes
/// it, and FINs when the dispatcher is exhausted. Cancel is checked per chunk.
#[allow(clippy::too_many_arguments)]
async fn data_send_task(
    conn: quinn::Connection,
    control: Arc<ControlState>,
    file: Arc<std::fs::File>,
    dispatcher: Arc<std::sync::atomic::AtomicU64>,
    sent_bytes: Arc<std::sync::atomic::AtomicU64>,
    leaves: Arc<Mutex<Vec<[u8; 32]>>>,
    have: Arc<Vec<u64>>,
    size: u64,
    chunk_size: u32,
    total_chunks: u64,
    session_id: &str,
    file_id: &str,
) -> Result<(), String> {
    let (mut send, _recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
    write_all_bounded(&mut send, &MAGIC_DATA.to_be_bytes()).await?;
    write_str(&mut send, session_id).await?;
    write_str(&mut send, file_id).await?;

    loop {
        if control.has(ControlState::CANCELLED) {
            let _ = send.reset(2u32.into());
            return Err("cancelled".to_string());
        }
        let idx = dispatcher.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        if idx >= total_chunks {
            break;
        }
        let abs_offset = idx * chunk_size as u64;
        let len = (size - abs_offset).min(chunk_size as u64) as usize;

        // Pooled slab per chunk (len ≤ chunk_size ≤ SLAB_SIZE); pread on the
        // blocking pool with the slab moved in and handed back out. The bounded
        // acquire is the sender-side RAM bound — starvation errors out (→ TCP
        // fallback) instead of hanging the Dart await-for.
        let slab = {
            let file = file.clone();
            let mut slab = pool().acquire_timeout(IDLE_TIMEOUT).await?;
            tokio::task::spawn_blocking(move || -> std::io::Result<crate::engine::bufpool::Slab> {
                read_exact_at(&file, &mut slab[..len], abs_offset)?;
                Ok(slab)
            })
            .await
            .map_err(|e| e.to_string())?
            .map_err(|e| e.to_string())?
        };

        // Merkle leaf (Phase 1d) — computed for EVERY chunk (incl. resume-skipped
        // ones) so the whole-file root is complete. One writer per index.
        leaves.lock().unwrap()[idx as usize] = sha256_leaf(&slab[..len]);

        // Resume (Phase 4): the receiver already has this chunk — hashed above for
        // the root, but do NOT re-send it over the network (that is the saving).
        let already = have[(idx / 64) as usize] & (1 << (idx % 64)) != 0;
        if already {
            drop(slab);
            continue;
        }

        let mut header = [0u8; 17];
        header[..8].copy_from_slice(&abs_offset.to_be_bytes());
        header[8..12].copy_from_slice(&(len as u32).to_be_bytes());
        header[12..16].copy_from_slice(&crc32c::crc32c(&slab[..len]).to_be_bytes());
        header[16] = FRAME_FLAGS_NONE;
        write_all_bounded(&mut send, &header).await?;
        write_all_bounded(&mut send, &slab[..len]).await?;
        drop(slab); // back to the pool before the next acquire

        sent_bytes.fetch_add(len as u64, std::sync::atomic::Ordering::Relaxed);
    }
    send.finish().map_err(|e| e.to_string())?;
    // Wait for the receiver to consume the stream (resolves once it reads to
    // completion), so the control stream's ACK wait starts only after the data
    // actually drained. Bounded — an unbounded stopped() would reintroduce the
    // Phase 0 indefinite-stall bug. Generous (5×) because up to the flow-control
    // window can still legitimately be in flight on a slow link.
    match tokio::time::timeout(IDLE_TIMEOUT * 5, send.stopped()).await {
        Ok(_) => Ok(()),
        Err(_) => Err("data stream drain timeout".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end loopback: a real quinn server + client transfer a 500 KB file
    /// over QUIC/TLS1.3 and the received bytes must match exactly.
    #[test]
    fn quic_loopback_roundtrip() {
        quic_authorize_session("sess-1".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir().join(format!("bishare_quic_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let src = dir.join("payload.bin");
            let payload: Vec<u8> = (0..500_000u32).map(|i| (i % 251) as u8).collect();
            tokio::fs::write(&src, &payload).await.unwrap();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_s = dir.to_string_lossy().to_string();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (send, recv) = conn.accept_bi().await.unwrap();
                let ev = stream_dispatch(send, recv, &dir_s, None, IDLE_TIMEOUT)
                    .await
                    .unwrap()
                    .expect("legacy stream must yield an event");
                conn.closed().await; // keep endpoint alive until client closes (ACK flush)
                ev
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let (send, recv) = conn.open_bi().await.unwrap();
            let control = Arc::new(ControlState::default());
            let sent = stream_send(
                send, recv, &control, "sess-1", "file-1", "iPhone", "fp-1",
                &src.to_string_lossy(), "payload.bin", "application/octet-stream", |_| {},
            )
            .await
            .unwrap();
            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            let ev = server.await.unwrap();
            assert_eq!(sent, payload.len() as u64);
            match ev {
                QuicServerEvent::Received {
                    session_id, file_id, sender_alias, file_name, temp_path, size, verified, ..
                } => {
                    assert_eq!(session_id, "sess-1");
                    assert_eq!(file_id, "file-1");
                    assert_eq!(sender_alias, "iPhone");
                    assert_eq!(file_name, "payload.bin");
                    assert_eq!(size, payload.len() as u64);
                    assert!(verified, "legacy path must integrity-verify (SHA-256)");
                    let got = tokio::fs::read(&temp_path).await.unwrap();
                    assert_eq!(got, payload, "received bytes must match sent bytes");
                }
                _ => panic!("expected Received event"),
            }

            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 0 regression: a sender that writes the header (declaring a non-zero
    /// size) then STALLS — never sending the body — must make the receiver time
    /// out and delete the `.part`, instead of pinning the task forever. The stall
    /// survives quinn's keep-alive (both ends alive), so only the per-read idle
    /// timeout can break it. Runs with a short idle timeout so the test is fast.
    #[test]
    fn quic_stalled_sender_times_out_and_cleans_part() {
        quic_authorize_session("sess-1".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_stall_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            let file_id = "stall-1";
            let temp_path = format!("{dir_s}/.quic-{file_id}.part");

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (send, recv) = conn.accept_bi().await.unwrap();
                // Short idle timeout so the stall is caught quickly. Return as soon
                // as the read times out — do NOT await conn.closed() here (the client
                // is blocked on `server.await`, so waiting for it would deadlock).
                stream_dispatch(
                    send,
                    recv,
                    &dir_recv,
                    None,
                    std::time::Duration::from_millis(300),
                )
                .await
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let (mut send, _recv) = conn.open_bi().await.unwrap();
            // Write a complete header declaring 1 MB, then send NOTHING more.
            write_str(&mut send, "sess-1").await.unwrap();
            write_str(&mut send, file_id).await.unwrap();
            write_str(&mut send, "iPhone").await.unwrap();
            write_str(&mut send, "fp-1").await.unwrap();
            write_str(&mut send, "big.bin").await.unwrap();
            write_str(&mut send, "application/octet-stream").await.unwrap();
            send.write_u64(1024 * 1024).await.unwrap(); // promise 1 MB, deliver 0
                                                        // ...then stall (keep the connection open, send no body).

            match server.await.unwrap() {
                Err(f) => {
                    assert!(
                        f.message.contains("idle timeout"),
                        "expected an idle-timeout error, got: {}",
                        f.message
                    );
                    // The failure must carry the session so the UI can clear its card.
                    assert_eq!(f.session_id.as_deref(), Some("sess-1"));
                }
                Ok(_) => panic!("stalled receive must error out, not succeed"),
            }
            assert!(
                !std::path::Path::new(&temp_path).exists(),
                "the partial .part must be cleaned up on timeout"
            );

            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;
            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 0 consent gate: a sender whose sessionId was never authorized (no TCP
    /// prepare-accept) must be REJECTED before any `.part` is staged.
    #[test]
    fn quic_unauthorized_session_rejected() {
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_unauth_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (send, recv) = conn.accept_bi().await.unwrap();
                stream_dispatch(send, recv, &dir_recv, None, IDLE_TIMEOUT).await
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let (mut send, _recv) = conn.open_bi().await.unwrap();
            // A sessionId that no test ever authorizes.
            write_str(&mut send, "sess-never-prepared").await.unwrap();

            match server.await.unwrap() {
                Err(f) => assert!(
                    f.message.contains("unauthorized"),
                    "expected an unauthorized-session rejection, got: {}",
                    f.message
                ),
                Ok(_) => panic!("unauthorized session must be rejected, not accepted"),
            }
            // Nothing may have been staged for the rejected session.
            let mut entries = tokio::fs::read_dir(&dir).await.unwrap();
            let mut parts = 0;
            while let Some(e) = entries.next_entry().await.unwrap() {
                if e.file_name().to_string_lossy().ends_with(".part") {
                    parts += 1;
                }
            }
            assert_eq!(parts, 0, "no .part may be created for a rejected session");

            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;
            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 1a: connection reuse. Multiple files ride ONE connection (one
    /// handshake) via `open_bi` per file — the server accepts a single connection
    /// yet receives every file. A per-file-handshake sender would need N
    /// connections; here the server only ever accepts one.
    #[test]
    fn quic_multi_file_one_connection() {
        quic_authorize_session("sess-multi".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_multi_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            let src = dir.join("f.bin");
            let payload: Vec<u8> = (0..50_000u32).map(|i| (i % 251) as u8).collect();
            tokio::fs::write(&src, &payload).await.unwrap();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                // Accept exactly ONE connection, then drain its streams (mirrors the
                // real quic_serve inner loop). A second connection is never accepted.
                let mut files = 0u32;
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                while let Ok((send, recv)) = conn.accept_bi().await {
                    if stream_dispatch(send, recv, &dir_recv, None, IDLE_TIMEOUT).await.is_ok() {
                        files += 1;
                    }
                }
                files
            });

            // Client: ONE handshake, then N files over the reused connection.
            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let control = Arc::new(ControlState::default());
            let n = 3u32;
            for i in 0..n {
                let (send, recv) = conn.open_bi().await.unwrap();
                let sent = stream_send(
                    send, recv, &control, "sess-multi", &format!("file-{i}"), "iPhone", "fp",
                    &src.to_string_lossy(), "f.bin", "application/octet-stream", |_| {},
                )
                .await
                .unwrap();
                assert_eq!(sent, payload.len() as u64);
            }
            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            let files = server.await.unwrap();
            assert_eq!(files, n, "all N files must arrive over the single reused connection");
            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 1b fuzz-lite: the data-frame header fields come off the network —
    /// every malformed geometry must be rejected by the pure validator.
    #[test]
    fn validate_chunk_properties() {
        let cs = 64 * 1024u32; // 64 KB chunks
        let size = 300_000u64; // 4 full chunks + 1 short tail (37 856 bytes)

        // Valid interior + tail chunks.
        assert_eq!(validate_chunk(0, cs, cs, size), Ok(0));
        assert_eq!(validate_chunk(3 * cs as u64, cs, cs, size), Ok(3));
        let tail = (size - 4 * cs as u64) as u32;
        assert_eq!(validate_chunk(4 * cs as u64, tail, cs, size), Ok(4));

        // Rejections.
        assert!(validate_chunk(0, 0, cs, size).is_err(), "zero len");
        assert!(validate_chunk(0, cs + 1, cs, size).is_err(), "len > chunk");
        assert!(validate_chunk(1, cs, cs, size).is_err(), "misaligned offset");
        assert!(validate_chunk(size, 1, cs, size).is_err(), "offset at EOF");
        assert!(validate_chunk(u64::MAX - 63, cs, cs, size).is_err(), "huge offset");
        assert!(validate_chunk(4 * cs as u64, cs, cs, size).is_err(), "tail overrun");
        assert!(validate_chunk(0, cs - 1, cs, size).is_err(), "short interior chunk");
        assert!(validate_chunk(4 * cs as u64, tail - 1, cs, size).is_err(), "short tail");
    }

    /// Phase 1d: the Merkle root is order-independent of ARRIVAL (leaves live at
    /// their chunk index, combined in index order) yet detects any tamper —
    /// exactly what the multi-stream integrity check relies on.
    #[test]
    fn merkle_root_order_independent_and_tamper_evident() {
        let (l0, l1, l2) = (
            sha256_leaf(b"chunk-zero"),
            sha256_leaf(b"chunk-one"),
            sha256_leaf(b"chunk-two"),
        );
        // Filled in index order vs reverse ARRIVAL order → identical root.
        let in_order = vec![l0, l1, l2];
        let mut reverse_arrival = vec![[0u8; 32]; 3];
        reverse_arrival[2] = l2;
        reverse_arrival[1] = l1;
        reverse_arrival[0] = l0;
        assert_eq!(merkle_root(&in_order), merkle_root(&reverse_arrival));

        // One chunk changed at an index → different root (integrity failure).
        let mut tampered = in_order.clone();
        tampered[1] = sha256_leaf(b"tampered");
        assert_ne!(merkle_root(&in_order), merkle_root(&tampered));
    }

    /// Duplicate chunks are a protocol violation (QUIC streams are reliable) and
    /// must be detected by the bitmap, not silently double-counted.
    #[test]
    fn chunk_bitmap_rejects_duplicates() {
        let mut bm = ChunkBitmap::new(130); // spans three u64 words
        assert!(bm.set(0));
        assert!(bm.set(64));
        assert!(bm.set(129));
        assert!(!bm.set(64), "duplicate must return false");
        assert_eq!(bm.received, 3);
        for i in 0..130 {
            bm.set(i);
        }
        assert_eq!(bm.received, 130);
    }

    /// Phase 1c: the RAM hard ceiling. A 32 MB file crosses the multi-stream
    /// path while the global slab pool proves data-plane RAM is INDEPENDENT of
    /// file size: no more than POOL_SLABS buffers are ever allocated, however
    /// much data moves. (Pattern-generated + streaming-verified so the test
    /// itself never holds the payload in memory either.)
    #[test]
    fn quic_bounded_ram_multi_stream() {
        use crate::engine::bufpool::{pool, POOL_SLABS};
        quic_authorize_session("sess-1c".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_ram_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            let src = dir.join("big.bin");

            // Write a 32 MB deterministic pattern in 1 MB slices (no big buffers).
            const MB: usize = 1024 * 1024;
            const TOTAL: usize = 32 * MB;
            let pattern = |off: usize| -> u8 { ((off / 7) as u8) ^ ((off % 251) as u8) };
            {
                let mut f = tokio::fs::File::create(&src).await.unwrap();
                let mut slice = vec![0u8; MB];
                for m in 0..(TOTAL / MB) {
                    for (i, b) in slice.iter_mut().enumerate() {
                        *b = pattern(m * MB + i);
                    }
                    tokio::io::AsyncWriteExt::write_all(&mut f, &slice).await.unwrap();
                }
                tokio::io::AsyncWriteExt::flush(&mut f).await.unwrap();
            }

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (tx, mut rx) =
                    tokio::sync::mpsc::unbounded_channel::<Result<QuicServerEvent, String>>();
                loop {
                    tokio::select! {
                        ev = rx.recv() => {
                            let ev = ev.expect("event channel closed");
                            conn.closed().await;
                            return ev;
                        }
                        accepted = conn.accept_bi() => {
                            let (send, recv) = accepted.expect("connection closed early");
                            let dir = dir_recv.clone();
                            let tx = tx.clone();
                            runtime().spawn(async move {
                                match stream_dispatch(send, recv, &dir, None, IDLE_TIMEOUT).await {
                                    Ok(Some(ev)) => { let _ = tx.send(Ok(ev)); }
                                    Ok(None) => {}
                                    Err(f) => { let _ = tx.send(Err(f.message)); }
                                }
                            });
                        }
                    }
                }
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let control = Arc::new(ControlState::default());
            let sent = stream_send_multi(
                &conn, &control, "sess-1c", "file-ram", "Mac", "fp",
                &src.to_string_lossy(), "big.bin", "application/octet-stream",
                4, MAX_CHUNK, None, |_| {},
            )
            .await
            .unwrap();
            assert_eq!(sent, TOTAL as u64);

            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            let ev = server.await.unwrap().unwrap();
            let temp_path = match ev {
                QuicServerEvent::Received { temp_path, size, .. } => {
                    assert_eq!(size, TOTAL as u64);
                    temp_path
                }
                _ => panic!("expected Received event"),
            };

            // Streaming verification — 1 MB at a time.
            {
                let mut f = tokio::fs::File::open(&temp_path).await.unwrap();
                let mut slice = vec![0u8; MB];
                for m in 0..(TOTAL / MB) {
                    tokio::io::AsyncReadExt::read_exact(&mut f, &mut slice).await.unwrap();
                    for (i, b) in slice.iter().enumerate() {
                        assert_eq!(*b, pattern(m * MB + i), "byte mismatch at {}", m * MB + i);
                    }
                }
            }

            // THE Phase 1c invariant: 32 MB moved, yet slab memory never exceeded
            // the pool cap — data-plane RAM is independent of file size.
            let (cap, allocated, _in_use, peak, acquires) = pool().stats();
            assert!(
                allocated <= POOL_SLABS,
                "pool must never allocate beyond its cap (allocated={allocated})"
            );
            assert!(peak <= cap, "peak in-use must respect the ceiling");
            assert!(acquires >= 32, "the transfer must actually have used the pool");

            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 4: resume. A `.part` pre-seeded with chunks 0,1,2 + a matching
    /// ledger is resumed — the sender skips those (proven by the receiver's
    /// duplicate-chunk guard: re-sending an already-have chunk would FAIL), sends
    /// only chunks 3,4, re-hashes the have-chunks from disk, and the whole file
    /// verifies byte-exact.
    #[test]
    fn quic_resume_skips_have_chunks() {
        quic_authorize_session("sess-resume".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_rz_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            let cs = MIN_CHUNK as usize; // 64 KB
            let size = 300_000usize; // 5 chunks (last short)
            let payload: Vec<u8> = (0..size as u32).map(|i| (i % 251) as u8).collect();
            let src = dir.join("resume.bin");
            tokio::fs::write(&src, &payload).await.unwrap();

            // Pre-seed the receiver's partial: chunks 0,1,2 present, correct bytes.
            let resume_key = derive_resume_key("fp-r", "resume.bin", size as u64);
            let part = format!("{dir_s}/{}", resume_part_name(&resume_key));
            {
                let f = std::fs::File::create(&part).unwrap();
                f.set_len(size as u64).unwrap();
                write_all_at(&f, &payload[..3 * cs], 0).unwrap();
                f.sync_all().unwrap();
            }
            let meta = crate::engine::resume::LedgerMeta {
                size: size as u64,
                chunk_size: cs as u32,
                total_chunks: 5,
                resume_key: &resume_key,
            };
            crate::engine::resume::save(&part, &meta, &[0b111u64]).unwrap();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (tx, mut rx) =
                    tokio::sync::mpsc::unbounded_channel::<Result<QuicServerEvent, String>>();
                loop {
                    tokio::select! {
                        ev = rx.recv() => { let ev = ev.expect("closed"); conn.closed().await; return ev; }
                        accepted = conn.accept_bi() => {
                            let (send, recv) = accepted.expect("conn closed early");
                            let dir = dir_recv.clone();
                            let tx = tx.clone();
                            runtime().spawn(async move {
                                match stream_dispatch(send, recv, &dir, None, IDLE_TIMEOUT).await {
                                    Ok(Some(ev)) => { let _ = tx.send(Ok(ev)); }
                                    Ok(None) => {}
                                    Err(f) => { let _ = tx.send(Err(f.message)); }
                                }
                            });
                        }
                    }
                }
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let control = Arc::new(ControlState::default());
            let sent = stream_send_multi(
                &conn, &control, "sess-resume", "file-r", "Mac", "fp-r",
                &src.to_string_lossy(), "resume.bin", "application/octet-stream",
                2, MIN_CHUNK, Some(&resume_key), |_| {},
            )
            .await
            .unwrap();
            assert_eq!(sent, size as u64);

            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            match server.await.unwrap().unwrap() {
                QuicServerEvent::Received { temp_path, verified, .. } => {
                    assert!(verified, "resumed file must verify (re-hash + gaps)");
                    // Success PROVES the have-chunks were skipped: re-sending any
                    // of 0,1,2 would trip the duplicate-chunk guard and fail.
                    let got = tokio::fs::read(&temp_path).await.unwrap();
                    assert_eq!(got, payload, "resumed file must be byte-exact");
                    // Ledger removed on completion.
                    assert!(!std::path::Path::new(&crate::engine::resume::ledger_path(&part)).exists());
                }
                _ => panic!("expected Received"),
            }
            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 3: the loopback benchmark harness runs end-to-end and reports a
    /// verified transfer with plausible numbers + connection stats.
    /// `#[ignore]`: it moves a real 8 MB through the shared global runtime + slab
    /// pool, so it flakes when racing the other heavy transfer tests in parallel.
    /// Run it (and the perf sweep) explicitly: `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn quic_benchmark_smoke() {
        let json = quic_benchmark(8, 2, 256).expect("benchmark must succeed");
        assert!(json.contains("\"mbps\":"), "has throughput: {json}");
        assert!(json.contains("\"verified\":true"), "must verify: {json}");
        assert!(json.contains("\"mtu\":"), "has conn stats: {json}");
        assert!(json.contains("\"aes_armv8\":"), "has build flag: {json}");
    }

    /// HW-AES MUST be compiled in on aarch64 (Apple silicon, modern ARM). A build
    /// that lost the `aes_armv8` cfg runs AES-256-GCM ~11× slower (constant-time
    /// software) with NO build error — exactly the 2026-07-13 Apple regression
    /// (cargo didn't find `rust/.cargo/config.toml` because cargokit ran it from a
    /// CWD outside the project; fixed by running cargo with
    /// `workingDirectory=manifestDir`). Unlike `quic_benchmark_smoke` this is NOT
    /// `#[ignore]`, so a normal `cargo test` on any aarch64 host (dev Macs, an
    /// aarch64 CI runner) fails loudly if the flag ever drops again. x86 reaches
    /// AES-NI via a different cfg, so this guard is aarch64-scoped.
    #[test]
    #[cfg(target_arch = "aarch64")]
    fn hw_aes_active_on_aarch64() {
        assert!(
            crate::engine::metrics::hw_aes_active(),
            "aes_armv8 cfg is OFF on aarch64 — AES-256-GCM would run ~11× slower (software). \
             On Apple this means cargo did not pick up rust/.cargo/config.toml; cargokit must run \
             cargo with workingDirectory=manifestDir (see builder.dart)."
        );
    }

    /// Phase 2b: TWO files stream CONCURRENTLY over ONE connection (interleaved
    /// control+data streams for different fileIds) — the receiver's per-(session,
    /// file) registry must reassemble and verify both.
    #[test]
    fn quic_concurrent_files_one_connection() {
        quic_authorize_session("sess-2b".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_cc_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            // Two distinct payloads (different sizes → distinct chunk tails).
            let pay_a: Vec<u8> = (0..300_000u32).map(|i| (i % 251) as u8).collect();
            let pay_b: Vec<u8> = (0..200_001u32).map(|i| ((i * 7) % 249) as u8).collect();
            let src_a = dir.join("a.bin");
            let src_b = dir.join("b.bin");
            tokio::fs::write(&src_a, &pay_a).await.unwrap();
            tokio::fs::write(&src_b, &pay_b).await.unwrap();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                // Collect TWO Received events, then hold until the client closes.
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (tx, mut rx) =
                    tokio::sync::mpsc::unbounded_channel::<Result<QuicServerEvent, String>>();
                let mut events = Vec::new();
                loop {
                    tokio::select! {
                        ev = rx.recv() => {
                            events.push(ev.expect("event channel closed"));
                            if events.len() == 2 {
                                conn.closed().await;
                                return events;
                            }
                        }
                        accepted = conn.accept_bi() => {
                            let (send, recv) = accepted.expect("connection closed early");
                            let dir = dir_recv.clone();
                            let tx = tx.clone();
                            runtime().spawn(async move {
                                match stream_dispatch(send, recv, &dir, None, IDLE_TIMEOUT).await {
                                    Ok(Some(ev)) => { let _ = tx.send(Ok(ev)); }
                                    Ok(None) => {}
                                    Err(f) => { let _ = tx.send(Err(f.message)); }
                                }
                            });
                        }
                    }
                }
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let control = Arc::new(ControlState::default());

            // Send both files CONCURRENTLY (2 streams each = 4 data + 2 control).
            let (ca, cb) = (control.clone(), control.clone());
            let (conn_a, conn_b) = (conn.clone(), conn.clone());
            let (pa, pb) = (src_a.to_string_lossy().to_string(), src_b.to_string_lossy().to_string());
            let send_a = runtime().spawn(async move {
                stream_send_multi(
                    &conn_a, &ca, "sess-2b", "file-a", "Mac", "fp", &pa, "a.bin",
                    "application/octet-stream", 2, MIN_CHUNK, None, |_| {},
                )
                .await
            });
            let send_b = runtime().spawn(async move {
                stream_send_multi(
                    &conn_b, &cb, "sess-2b", "file-b", "Mac", "fp", &pb, "b.bin",
                    "application/octet-stream", 2, MIN_CHUNK, None, |_| {},
                )
                .await
            });
            assert_eq!(send_a.await.unwrap().unwrap(), pay_a.len() as u64);
            assert_eq!(send_b.await.unwrap().unwrap(), pay_b.len() as u64);

            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            let events = server.await.unwrap();
            let mut seen = std::collections::HashMap::new();
            for ev in events {
                match ev.unwrap() {
                    QuicServerEvent::Received { file_id, temp_path, size, verified, .. } => {
                        assert!(verified, "concurrent files must both verify");
                        seen.insert(file_id, (temp_path, size));
                    }
                    _ => panic!("expected Received"),
                }
            }
            let (path_a, size_a) = &seen["file-a"];
            let (path_b, size_b) = &seen["file-b"];
            assert_eq!(*size_a, pay_a.len() as u64);
            assert_eq!(*size_b, pay_b.len() as u64);
            assert_eq!(tokio::fs::read(path_a).await.unwrap(), pay_a);
            assert_eq!(tokio::fs::read(path_b).await.unwrap(), pay_b);

            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }

    /// Phase 1b end-to-end: a file sent as offset-framed chunks over FOUR
    /// parallel data streams (+1 control stream) arrives byte-identical, with
    /// the Received event emitted by the control stream.
    #[test]
    fn quic_multi_stream_loopback() {
        quic_authorize_session("sess-1b".to_string());
        runtime().block_on(async {
            let dir = std::env::temp_dir()
                .join(format!("bishare_quic_ms_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let dir_s = dir.to_string_lossy().to_string();
            let src = dir.join("payload.bin");
            // 300 000 bytes @ 64 KB chunks = 5 chunks over 4 streams (last short).
            let payload: Vec<u8> = (0..300_000u32).map(|i| (i % 251) as u8).collect();
            tokio::fs::write(&src, &payload).await.unwrap();

            let server_ep =
                tuned_server_endpoint(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_recv = dir_s.clone();
            let server = runtime().spawn(async move {
                // Mirror quic_serve's inner loop: dispatch every accepted stream,
                // forward the (single) Received event out of the spawned tasks.
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (tx, mut rx) =
                    tokio::sync::mpsc::unbounded_channel::<Result<QuicServerEvent, String>>();
                loop {
                    tokio::select! {
                        ev = rx.recv() => {
                            let ev = ev.expect("event channel closed");
                            // Keep the connection alive until the client closes it,
                            // or dropping `conn` here races the ACK delivery.
                            conn.closed().await;
                            return ev;
                        }
                        accepted = conn.accept_bi() => {
                            let (send, recv) = accepted.expect("connection closed early");
                            let dir = dir_recv.clone();
                            let tx = tx.clone();
                            runtime().spawn(async move {
                                match stream_dispatch(send, recv, &dir, None, IDLE_TIMEOUT).await {
                                    Ok(Some(ev)) => { let _ = tx.send(Ok(ev)); }
                                    Ok(None) => {} // data stream
                                    Err(f) => { let _ = tx.send(Err(f.message)); }
                                }
                            });
                        }
                    }
                }
            });

            let mut client_ep = tuned_client_endpoint("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let control = Arc::new(ControlState::default());
            let mut last_progress = 0u64;
            let sent = stream_send_multi(
                &conn,
                &control,
                "sess-1b",
                "file-ms",
                "Mac",
                "fp-ms",
                &src.to_string_lossy(),
                "payload.bin",
                "application/octet-stream",
                4,
                MIN_CHUNK,
                None,
                |n| last_progress = n,
            )
            .await
            .unwrap();
            assert_eq!(sent, payload.len() as u64);
            assert_eq!(last_progress, payload.len() as u64, "final progress = size");

            // Close BEFORE awaiting the server — it holds the connection open
            // (conn.closed().await) until the client closes, so awaiting it first
            // deadlocks. The ACK already confirmed full delivery.
            conn.close(0u32.into(), b"done");
            client_ep.wait_idle().await;

            let ev = server.await.unwrap().unwrap();
            match ev {
                QuicServerEvent::Received {
                    session_id, file_id, sender_alias, file_name, temp_path, size, verified, ..
                } => {
                    assert_eq!(session_id, "sess-1b");
                    assert_eq!(file_id, "file-ms");
                    assert_eq!(sender_alias, "Mac");
                    assert_eq!(file_name, "payload.bin");
                    assert_eq!(size, payload.len() as u64);
                    assert!(verified, "multi-stream must verify the Merkle root");
                    let got = tokio::fs::read(&temp_path).await.unwrap();
                    assert_eq!(got, payload, "multi-stream reassembly must be byte-exact");
                }
                _ => panic!("expected Received event"),
            }

            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }
}
