//! Transfer metrics (Phase 3, hte-architecture.md §2.2/§18): compact JSON
//! snapshots of quinn connection stats — the ground truth for attributing
//! throughput (RTT, cwnd, ACTUAL negotiated MTU from DPLPMTUD, loss, datagram
//! I/O counts) — plus the buffer-pool counters and build flags. Hand-formatted
//! JSON (fixed small field set) to avoid pulling serde into the hot crate.

use crate::engine::bufpool::pool;

/// Whether the ARMv8 hardware-AES cfg was active for this build — surfaced in
/// benchmark JSON so CI can assert the cargokit flag injection still works
/// (hte-architecture.md §9: the cfg silently dropping = ~11× slower TCP AES).
#[allow(unexpected_cfgs)]
pub fn hw_aes_active() -> bool {
    cfg!(aes_armv8)
}

/// Compact JSON of a live connection's path/transport stats.
pub fn conn_stats_json(conn: &quinn::Connection) -> String {
    let s = conn.stats();
    let (cap, allocated, in_use, peak, acquires) = pool().stats();
    format!(
        concat!(
            "{{\"rtt_us\":{},\"cwnd\":{},\"mtu\":{},\"congestion_events\":{},",
            "\"lost_packets\":{},\"lost_bytes\":{},",
            "\"udp_tx_datagrams\":{},\"udp_tx_bytes\":{},\"udp_tx_ios\":{},",
            "\"udp_rx_datagrams\":{},\"udp_rx_bytes\":{},\"udp_rx_ios\":{},",
            "\"pool_slabs\":{},\"pool_allocated\":{},\"pool_in_use\":{},",
            "\"pool_peak\":{},\"pool_acquires\":{},\"aes_armv8\":{}}}"
        ),
        s.path.rtt.as_micros(),
        s.path.cwnd,
        s.path.current_mtu,
        s.path.congestion_events,
        s.path.lost_packets,
        s.path.lost_bytes,
        s.udp_tx.datagrams,
        s.udp_tx.bytes,
        s.udp_tx.ios,
        s.udp_rx.datagrams,
        s.udp_rx.bytes,
        s.udp_rx.ios,
        cap,
        allocated,
        in_use,
        peak,
        acquires,
        hw_aes_active(),
    )
}
