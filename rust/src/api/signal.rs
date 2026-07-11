//! MediaSignal (0x11) framing for WebRTC signaling over the LAN TCP link
//! (Remote Camera / Screen Mirroring). Payloads cross the FFI as JSON strings
//! of `bishare_protocol::models::SignalEnvelope` — cheap, and avoids mirroring
//! the struct into FRB. v2.4 frame: never emit to a peer without
//! `supportsMedia` (gating lives in Dart, later waves).

use bishare_protocol::binary::{DecodeResult, Decoder, Encoder, MessageType};
use bishare_protocol::models::SignalEnvelope;

/// Frame a `SignalEnvelope` JSON string as a MediaSignal (0x11) frame.
/// Round-trips through the protocol struct so the wire payload is exactly what
/// the peer's decoder expects (unknown/misspelled fields fail here, not there).
pub fn encode_media_signal(env_json: String) -> Result<Vec<u8>, String> {
    let env: SignalEnvelope =
        serde_json::from_str(&env_json).map_err(|e| format!("invalid SignalEnvelope: {e}"))?;
    Encoder::encode_json(MessageType::MediaSignal, 0, &env)
        .ok_or_else(|| "failed to encode MediaSignal frame".to_string())
}

/// Decode a complete MediaSignal (0x11) frame back into its `SignalEnvelope`
/// JSON string.
pub fn decode_media_signal(bytes: Vec<u8>) -> Result<String, String> {
    let frame = match Decoder::decode(&bytes) {
        DecodeResult::Success { frame, .. } => frame,
        DecodeResult::NeedMoreData => return Err("incomplete MediaSignal frame".to_string()),
        DecodeResult::Error(e) => return Err(e),
    };
    if frame.msg_type != MessageType::MediaSignal {
        return Err(format!(
            "expected MediaSignal (0x11), got 0x{:02X}",
            frame.msg_type as u8
        ));
    }
    let env: SignalEnvelope = Decoder::decode_json(&frame)
        .ok_or_else(|| "malformed MediaSignal payload".to_string())?;
    serde_json::to_string(&env).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offer_json() -> String {
        r#"{"type":"offer","sessionId":"s-1","media":"camera","sdp":"v=0","sender":"fp","alias":"Mac"}"#
            .to_string()
    }

    #[test]
    fn test_media_signal_roundtrip() {
        let bytes = encode_media_signal(offer_json()).unwrap();
        assert_eq!(bytes[0], 0x11); // wire byte stays MediaSignal
        let json = decode_media_signal(bytes).unwrap();
        let env: SignalEnvelope = serde_json::from_str(&json).unwrap();
        assert_eq!(env.type_, "offer");
        assert_eq!(env.session_id, "s-1");
        assert_eq!(env.sdp.as_deref(), Some("v=0"));
        // None fields must stay skipped on the wire (legacy-safe JSON)
        assert!(!json.contains("candidate"));
    }

    #[test]
    fn test_encode_rejects_bad_json() {
        assert!(encode_media_signal("{".to_string()).is_err());
        assert!(encode_media_signal(r#"{"type":"offer"}"#.to_string()).is_err());
    }

    #[test]
    fn test_decode_rejects_wrong_frame_type() {
        let frame = Encoder::encode(MessageType::Ack, 0, b"{}");
        assert!(decode_media_signal(frame).is_err());
        assert!(decode_media_signal(vec![0x11, 0x00]).is_err()); // truncated
    }
}
