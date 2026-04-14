use agent::wire::{decode_ws_binary_message, encode_ws_binary_message};
use proto_gen::{envelope::Payload, ClientType, Envelope, Handshake};

#[test]
fn single_envelope_binary_frame_round_trips_with_four_byte_length_prefix() {
    let envelope = Envelope {
        protocol_version: 1,
        request_id: "req-1".into(),
        timestamp_ms: 1,
        payload: Some(Payload::Handshake(Handshake {
            protocol_version: 1,
            client_type: ClientType::PhoneIos as i32,
            client_version: "1.0.0".into(),
            device_id: "device".into(),
        })),
    };

    let frame = encode_ws_binary_message(&envelope).expect("encode frame");

    let payload_len = u32::from_be_bytes(frame[..4].try_into().expect("prefix bytes")) as usize;
    assert_eq!(frame.len(), payload_len + 4);

    let decoded = decode_ws_binary_message(&frame).expect("frame should decode");

    assert_eq!(decoded.request_id, "req-1");
    assert_eq!(decoded.protocol_version, 1);
}
