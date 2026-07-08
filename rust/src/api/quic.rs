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
//!   `[str sessionId][str fileId][str fileName][str fileType][u64 size][size bytes]`
//! where `str` = `[u32 len][utf8 bytes]`. Reply: 1 ACK byte.

use std::collections::HashMap;
use std::net::{Ipv6Addr, SocketAddr};
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::OnceLock;

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

/// Flow-control + keep-alive tuning. quinn's defaults cap a single stream at
/// ~1.25 MB in flight → ~20 MB/s on a fast LAN. Large windows let one stream
/// saturate the link (≥40 MB/s), matching the TCP path.
fn transport_config() -> Arc<quinn::TransportConfig> {
    let mut t = quinn::TransportConfig::default();
    t.stream_receive_window(quinn::VarInt::from_u32(16 * 1024 * 1024)); // 16 MB / stream
    t.receive_window(quinn::VarInt::from_u32(64 * 1024 * 1024)); // 64 MB / connection
    t.send_window(64 * 1024 * 1024);
    t.max_idle_timeout(Some(
        std::time::Duration::from_secs(30).try_into().unwrap(),
    ));
    t.keep_alive_interval(Some(std::time::Duration::from_secs(5)));
    Arc::new(t)
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
    if len > MAX_STR {
        return Err(format!("string too long: {len}"));
    }
    let mut buf = vec![0u8; len];
    recv.read_exact(&mut buf).await.map_err(|e| e.to_string())?;
    Ok(String::from_utf8_lossy(&buf).to_string())
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
    /// A non-fatal receive error.
    Error { message: String },
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

/// Cancel-token registry: an in-flight [quic_send_file] checks its `cancel_id`
/// each chunk and aborts (resetting the stream) once it's here.
fn cancels() -> &'static Mutex<std::collections::HashSet<String>> {
    static C: OnceLock<Mutex<std::collections::HashSet<String>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(std::collections::HashSet::new()))
}

/// Cancel the in-flight QUIC send tagged with [cancel_id].
#[frb(sync)]
pub fn quic_cancel(cancel_id: String) {
    cancels().lock().unwrap().insert(cancel_id);
}

fn is_cancelled(cancel_id: &str) -> bool {
    cancels().lock().unwrap().contains(cancel_id)
}

fn clear_cancel(cancel_id: &str) {
    cancels().lock().unwrap().remove(cancel_id);
}

/// Start a QUIC server on `[::]:port`, staging received files as `.part` files in
/// `save_dir`. Emits [QuicServerEvent]s to Dart; the first is `Ready` (or `Error`
/// on bind failure). Stop it with [quic_stop].
pub fn quic_serve(sink: StreamSink<QuicServerEvent>, port: u16, save_dir: String) {
    let cfg = match server_config() {
        Ok(c) => c,
        Err(message) => {
            let _ = sink.add(QuicServerEvent::Error { message });
            return;
        }
    };
    let addr = SocketAddr::new(Ipv6Addr::UNSPECIFIED.into(), port);
    let endpoint = match runtime().block_on(async { Endpoint::server(cfg, addr) }) {
        Ok(ep) => ep,
        Err(e) => {
            let _ = sink.add(QuicServerEvent::Error {
                message: format!("bind {port}: {e}"),
            });
            return;
        }
    };
    servers().lock().unwrap().insert(port, endpoint.clone());
    runtime().spawn(async move {
        let _ = sink.add(QuicServerEvent::Ready);
        while let Some(incoming) = endpoint.accept().await {
            let sink = sink.clone();
            let dir = save_dir.clone();
            runtime().spawn(async move {
                if let Ok(conn) = incoming.await {
                    while let Ok((send, recv)) = conn.accept_bi().await {
                        let sink = sink.clone();
                        let dir = dir.clone();
                        runtime().spawn(async move {
                            match stream_recv(send, recv, &dir, Some(&sink)).await {
                                Ok(ev) => {
                                    let _ = sink.add(ev);
                                }
                                Err(message) => {
                                    let _ = sink.add(QuicServerEvent::Error { message });
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
) -> Result<(), String> {
    /// Emit progress at most this often (bytes) — matches the TCP path's ~12/s.
    const PROGRESS_EVERY: u64 = 4 * 1024 * 1024;
    let mut remaining = size;
    let mut received: u64 = 0;
    let mut last_emit: u64 = 0;
    let mut buf = vec![0u8; READ_CHUNK];
    while remaining > 0 {
        let want = remaining.min(READ_CHUNK as u64) as usize;
        let n = recv
            .read(&mut buf[..want])
            .await
            .map_err(|e| e.to_string())?
            .ok_or_else(|| "stream ended early".to_string())?;
        file.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
        remaining -= n as u64;
        received += n as u64;
        if let Some(sink) = sink {
            if received - last_emit >= PROGRESS_EVERY {
                last_emit = received;
                let _ = sink.add(QuicServerEvent::Progress {
                    session_id: session_id.to_string(),
                    file_id: file_id.to_string(),
                    file_name: file_name.to_string(),
                    received,
                    total: size,
                });
            }
        }
    }
    file.flush().await.map_err(|e| e.to_string())
}

/// Core receive: parse the header, stream the body into `save_dir/.quic-<fileId>.part`,
/// ACK one byte. Returns the [QuicServerEvent::Received] to emit. StreamSink-free.
async fn stream_recv(
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    save_dir: &str,
    sink: Option<&StreamSink<QuicServerEvent>>,
) -> Result<QuicServerEvent, String> {
    let session_id = read_str(&mut recv).await?;
    let file_id = read_str(&mut recv).await?;
    let sender_alias = read_str(&mut recv).await?;
    let sender_fingerprint = read_str(&mut recv).await?;
    let file_name = read_str(&mut recv).await?;
    let file_type = read_str(&mut recv).await?;
    let size = recv.read_u64().await.map_err(|e| e.to_string())?;

    tokio::fs::create_dir_all(save_dir).await.map_err(|e| e.to_string())?;
    let safe_id: String = file_id.chars().filter(|c| c.is_alphanumeric() || *c == '-').collect();
    let temp_path = format!("{save_dir}/.quic-{safe_id}.part");
    let mut file = tokio::fs::File::create(&temp_path).await.map_err(|e| e.to_string())?;

    // On cancel/error the sender resets the stream — drop the partial `.part` so a
    // cancelled transfer leaves nothing behind.
    if let Err(e) =
        drain_to_file(&mut recv, &mut file, size, sink, &session_id, &file_id, &file_name).await
    {
        drop(file);
        let _ = tokio::fs::remove_file(&temp_path).await;
        return Err(e);
    }

    send.write_all(&[1u8]).await.map_err(|e| e.to_string())?;
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
    })
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Send one file to `host:port` over QUIC, reporting bytes-sent progress. Returns
/// total bytes sent once the receiver ACKs. `session_id`/`file_id` correlate the
/// transfer with the TCP `prepare` the sender did first.
#[allow(clippy::too_many_arguments)]
pub fn quic_send_file(
    sink: StreamSink<u64>,
    host: String,
    port: u16,
    cancel_id: String,
    session_id: String,
    file_id: String,
    sender_alias: String,
    sender_fingerprint: String,
    file_path: String,
    file_name: String,
    file_type: String,
) -> Result<u64, String> {
    let out = runtime().block_on(async {
        let mut endpoint =
            Endpoint::client(SocketAddr::new(Ipv6Addr::UNSPECIFIED.into(), 0))
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

        let (send, recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
        let sent = stream_send(
            send,
            recv,
            &cancel_id,
            &session_id,
            &file_id,
            &sender_alias,
            &sender_fingerprint,
            &file_path,
            &file_name,
            &file_type,
            |n| {
                let _ = sink.add(n);
            },
        )
        .await;

        // On cancel/error close the connection so the receiver drops the partial.
        match sent {
            Ok(n) => {
                conn.close(0u32.into(), b"done");
                endpoint.wait_idle().await;
                Ok(n)
            }
            Err(e) => {
                conn.close(1u32.into(), b"cancel");
                Err(e)
            }
        }
    });
    clear_cancel(&cancel_id);
    out
}

/// Core send: write header + body on a bi stream, report progress, await the ACK.
#[allow(clippy::too_many_arguments)]
async fn stream_send(
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    cancel_id: &str,
    session_id: &str,
    file_id: &str,
    sender_alias: &str,
    sender_fingerprint: &str,
    file_path: &str,
    file_name: &str,
    file_type: &str,
    mut on_progress: impl FnMut(u64),
) -> Result<u64, String> {
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
    let mut buf = vec![0u8; READ_CHUNK];
    let mut sent = 0u64;
    loop {
        // Abort mid-stream on cancel — reset() makes the receiver's read fail so it
        // discards the partial `.part` instead of finalising it.
        if is_cancelled(cancel_id) {
            let _ = send.reset(2u32.into());
            return Err("cancelled".to_string());
        }
        let n = file.read(&mut buf).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        send.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
        sent += n as u64;
        on_progress(sent);
    }
    send.finish().map_err(|e| e.to_string())?;

    let mut ack = [0u8; 1];
    recv.read_exact(&mut ack).await.map_err(|e| e.to_string())?;
    Ok(sent)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end loopback: a real quinn server + client transfer a 500 KB file
    /// over QUIC/TLS1.3 and the received bytes must match exactly.
    #[test]
    fn quic_loopback_roundtrip() {
        runtime().block_on(async {
            let dir = std::env::temp_dir().join(format!("bishare_quic_{}", std::process::id()));
            tokio::fs::create_dir_all(&dir).await.unwrap();
            let src = dir.join("payload.bin");
            let payload: Vec<u8> = (0..500_000u32).map(|i| (i % 251) as u8).collect();
            tokio::fs::write(&src, &payload).await.unwrap();

            let server_ep =
                Endpoint::server(server_config().unwrap(), "127.0.0.1:0".parse().unwrap()).unwrap();
            let port = server_ep.local_addr().unwrap().port();
            let dir_s = dir.to_string_lossy().to_string();
            let server = runtime().spawn(async move {
                let conn = server_ep.accept().await.unwrap().await.unwrap();
                let (send, recv) = conn.accept_bi().await.unwrap();
                let ev = stream_recv(send, recv, &dir_s, None).await.unwrap();
                conn.closed().await; // keep endpoint alive until client closes (ACK flush)
                ev
            });

            let mut client_ep = Endpoint::client("127.0.0.1:0".parse().unwrap()).unwrap();
            client_ep.set_default_client_config(client_config().unwrap());
            let conn = client_ep
                .connect(format!("127.0.0.1:{port}").parse().unwrap(), "bishare")
                .unwrap()
                .await
                .unwrap();
            let (send, recv) = conn.open_bi().await.unwrap();
            let sent = stream_send(
                send, recv, "cancel-1", "sess-1", "file-1", "iPhone", "fp-1",
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
                    session_id, file_id, sender_alias, file_name, temp_path, size, ..
                } => {
                    assert_eq!(session_id, "sess-1");
                    assert_eq!(file_id, "file-1");
                    assert_eq!(sender_alias, "iPhone");
                    assert_eq!(file_name, "payload.bin");
                    assert_eq!(size, payload.len() as u64);
                    let got = tokio::fs::read(&temp_path).await.unwrap();
                    assert_eq!(got, payload, "received bytes must match sent bytes");
                }
                _ => panic!("expected Received event"),
            }

            let _ = tokio::fs::remove_dir_all(&dir).await;
        });
    }
}
