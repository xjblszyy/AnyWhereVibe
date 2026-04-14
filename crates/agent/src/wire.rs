use anyhow::{bail, ensure, Context, Result};
use prost::Message;
use proto_gen::Envelope;

pub fn encode_ws_binary_message(envelope: &Envelope) -> Result<Vec<u8>> {
    let payload = envelope.encode_to_vec();
    let length = payload.len() as u32;
    let mut frame = Vec::with_capacity(payload.len() + 4);
    frame.extend_from_slice(&length.to_be_bytes());
    frame.extend_from_slice(&payload);
    Ok(frame)
}

pub fn decode_ws_binary_message(bytes: &[u8]) -> Result<Envelope> {
    if bytes.len() < 4 {
        bail!("binary frame must include a 4-byte big-endian length prefix");
    }

    let expected_len = u32::from_be_bytes(
        bytes[..4]
            .try_into()
            .context("expected 4-byte big-endian length prefix")?,
    ) as usize;
    let payload = &bytes[4..];

    ensure!(
        payload.len() == expected_len,
        "binary frame length prefix {} does not match payload length {}",
        expected_len,
        payload.len()
    );

    Envelope::decode(payload).context("failed to decode protobuf envelope")
}
