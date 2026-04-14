use prost::Message;
use proto_gen::{envelope::Payload, ClientType, Envelope, Handshake};

#[test]
fn handshake_round_trip_preserves_protocol_and_device() {
    let envelope = Envelope {
        protocol_version: 1,
        request_id: "req-1".into(),
        timestamp_ms: 42,
        payload: Some(Payload::Handshake(Handshake {
            protocol_version: 1,
            client_type: ClientType::PhoneIos as i32,
            client_version: "1.0.0".into(),
            device_id: "iphone-1".into(),
        })),
    };

    let bytes = envelope.encode_to_vec();
    let decoded = Envelope::decode(bytes.as_slice()).unwrap();

    assert_eq!(decoded.protocol_version, 1);
    let handshake = match decoded.payload.unwrap() {
        Payload::Handshake(value) => value,
        other => panic!("unexpected payload: {other:?}"),
    };
    assert_eq!(handshake.device_id, "iphone-1");
}
