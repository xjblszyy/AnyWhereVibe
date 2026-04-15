use agent::wire::encode_ws_binary_message;
use futures_util::SinkExt;
use proto_gen::envelope::Payload;
use proto_gen::{ClientType, Envelope, ErrorEvent, Handshake};
use tokio_tungstenite::connect_async;

#[tokio::test]
async fn server_rejects_non_handshake_first_message() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(
            vec![0, 0, 0, 0],
        ))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_well_formed_non_handshake_envelope_as_first_message() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_first_message_status_request(&mut socket).await;

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}

#[tokio::test]
async fn server_rejects_text_frames_with_fatal_error_then_close() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_valid_handshake(&mut socket).await;
    agent::test_support::recv_agent_info(&mut socket).await;

    socket
        .send(tokio_tungstenite::tungstenite::Message::Text("bad".into()))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_protocol_version_mismatch() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_handshake_with_protocol(&mut socket, 999).await;

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "VERSION_MISMATCH");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_envelope_protocol_version_mismatch_even_when_handshake_payload_matches() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    let frame = encode_ws_binary_message(&Envelope {
        protocol_version: 999,
        request_id: "req-envelope-version".into(),
        timestamp_ms: 1,
        payload: Some(Payload::Handshake(Handshake {
            protocol_version: 1,
            client_type: ClientType::PhoneIos as i32,
            client_version: "1.0.0".into(),
            device_id: "device".into(),
        })),
    })
    .unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(
            frame,
        ))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "VERSION_MISMATCH");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_malformed_binary_frame_with_fatal_error() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(
            vec![0, 0, 0, 10, 1, 2],
        ))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}

#[tokio::test]
async fn server_rejects_validly_framed_but_non_protobuf_payload_with_fatal_error() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(
            vec![0, 0, 0, 3, 1, 2, 3],
        ))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}
