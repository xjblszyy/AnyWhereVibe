use agent::wire::{decode_ws_binary_message, encode_ws_binary_message};

#[test]
fn single_envelope_binary_frame_round_trips_with_four_byte_length_prefix() {
    let envelope = br#"{"kind":"hello","id":"abc-123"}"#.to_vec();

    let frame = encode_ws_binary_message(&envelope);

    assert_eq!(frame.len(), envelope.len() + 4);
    assert_eq!(
        u32::from_be_bytes(frame[..4].try_into().expect("prefix bytes")),
        envelope.len() as u32
    );

    let decoded = decode_ws_binary_message(&frame).expect("frame should decode");

    assert_eq!(decoded, envelope);
}
