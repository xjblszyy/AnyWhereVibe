use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use connection_node::db::Database;
use connection_node::registry::DeviceRegistry;
use connection_node::router::SessionRouter;
use connection_node::server;
use futures_util::{SinkExt, StreamExt};
use prost::Message as ProstMessage;
use proto_gen::envelope::Payload;
use proto_gen::{
    ConnectToDevice, ConnectionType, DeviceListRequest, DeviceListResponse, DeviceRegister,
    DeviceRegisterAck, DeviceType, Envelope,
};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;
use tokio::time::timeout;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

#[tokio::test]
async fn ws_first_message_must_be_device_register() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;
    let (mut socket, _) = connect_async(&ws_url).await.expect("connect");

    send_envelope(
        &mut socket,
        Envelope {
            protocol_version: 1,
            request_id: "req-list-first".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::DeviceListRequest(DeviceListRequest {})),
        },
    )
    .await;

    let next = timeout(Duration::from_secs(1), socket.next())
        .await
        .expect("socket close timeout");
    assert!(
        matches!(next, Some(Ok(Message::Close(_))) | None),
        "expected close, got {next:?}"
    );
}

#[tokio::test]
async fn valid_device_register_succeeds_and_invalid_token_fails() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let (mut valid_socket, _) = connect_async(&ws_url).await.expect("connect valid");
    send_device_register(
        &mut valid_socket,
        "req-valid",
        DeviceRegister {
            device_id: "alice-agent".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Alice Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;
    let ack = recv_device_register_ack(&mut valid_socket).await;
    assert!(ack.success);

    let (mut invalid_socket, _) = connect_async(&ws_url).await.expect("connect invalid");
    send_device_register(
        &mut invalid_socket,
        "req-invalid",
        DeviceRegister {
            device_id: "bad-agent".into(),
            auth_token: "mrt_ak_invalid".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Bad Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;
    let bad_ack = recv_device_register_ack(&mut invalid_socket).await;
    assert!(!bad_ack.success);
    assert!(bad_ack.message.contains("invalid auth token"));
}

#[tokio::test]
async fn device_list_request_returns_only_same_user_devices() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let (mut alice_phone, _) = connect_async(&ws_url).await.expect("connect alice phone");
    register_device(
        &mut alice_phone,
        DeviceRegister {
            device_id: "alice-phone".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Phone as i32,
            display_name: "Alice Phone".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut alice_agent, _) = connect_async(&ws_url).await.expect("connect alice agent");
    register_device(
        &mut alice_agent,
        DeviceRegister {
            device_id: "alice-agent".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Alice Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut bob_agent, _) = connect_async(&ws_url).await.expect("connect bob agent");
    register_device(
        &mut bob_agent,
        DeviceRegister {
            device_id: "bob-agent".into(),
            auth_token: "mrt_ak_bob1234567890abcdef".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Bob Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    send_envelope(
        &mut alice_phone,
        Envelope {
            protocol_version: 1,
            request_id: "req-device-list".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::DeviceListRequest(DeviceListRequest {})),
        },
    )
    .await;

    let response = recv_device_list_response(&mut alice_phone).await;
    let ids: Vec<_> = response
        .devices
        .into_iter()
        .map(|device| device.device_id)
        .collect();
    assert!(ids.contains(&"alice-phone".to_string()));
    assert!(ids.contains(&"alice-agent".to_string()));
    assert!(!ids.contains(&"bob-agent".to_string()));
}

#[tokio::test]
async fn connect_to_device_and_binary_frame_reaches_paired_side() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let (mut phone, _) = connect_async(&ws_url).await.expect("connect phone");
    register_device(
        &mut phone,
        DeviceRegister {
            device_id: "alice-phone".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Phone as i32,
            display_name: "Alice Phone".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut agent, _) = connect_async(&ws_url).await.expect("connect agent");
    register_device(
        &mut agent,
        DeviceRegister {
            device_id: "alice-agent".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Alice Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    send_envelope(
        &mut phone,
        Envelope {
            protocol_version: 1,
            request_id: "req-connect".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::ConnectToDevice(ConnectToDevice {
                target_device_id: "alice-agent".into(),
            })),
        },
    )
    .await;

    let ack = recv_connect_ack(&mut phone).await;
    assert!(ack.success);
    assert_eq!(ack.connection_type, ConnectionType::Relay as i32);

    phone
        .send(Message::Binary(vec![1, 2, 3, 4].into()))
        .await
        .expect("send binary");

    let routed = timeout(Duration::from_secs(1), agent.next())
        .await
        .expect("agent recv timeout")
        .expect("agent frame")
        .expect("agent ws ok");
    match routed {
        Message::Binary(bytes) => assert_eq!(bytes.to_vec(), vec![1, 2, 3, 4]),
        other => panic!("expected binary relay frame, got {other:?}"),
    }
}

#[tokio::test]
async fn connect_to_device_uses_requester_user_scope_when_device_ids_overlap() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let (mut phone, _) = connect_async(&ws_url).await.expect("connect phone");
    register_device(
        &mut phone,
        DeviceRegister {
            device_id: "shared-phone".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Phone as i32,
            display_name: "Alice Phone".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut alice_agent, _) = connect_async(&ws_url).await.expect("connect alice agent");
    register_device(
        &mut alice_agent,
        DeviceRegister {
            device_id: "shared-agent".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Alice Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut bob_agent, _) = connect_async(&ws_url).await.expect("connect bob agent");
    register_device(
        &mut bob_agent,
        DeviceRegister {
            device_id: "shared-agent".into(),
            auth_token: "mrt_ak_bob1234567890abcdef".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Bob Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    send_envelope(
        &mut phone,
        Envelope {
            protocol_version: 1,
            request_id: "req-connect-overlap".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::ConnectToDevice(ConnectToDevice {
                target_device_id: "shared-agent".into(),
            })),
        },
    )
    .await;

    let ack = recv_connect_ack(&mut phone).await;
    assert!(ack.success, "connect failed: {}", ack.message);

    phone
        .send(Message::Binary(vec![7, 7, 7].into()))
        .await
        .expect("send binary");

    let alice_frame = timeout(Duration::from_secs(1), alice_agent.next())
        .await
        .expect("alice recv timeout")
        .expect("alice frame")
        .expect("alice ws ok");
    match alice_frame {
        Message::Binary(bytes) => assert_eq!(bytes.to_vec(), vec![7, 7, 7]),
        other => panic!("expected alice binary relay frame, got {other:?}"),
    }

    let bob_frame = timeout(Duration::from_millis(200), bob_agent.next()).await;
    assert!(
        bob_frame.is_err(),
        "bob agent unexpectedly received a frame"
    );
}

#[tokio::test]
async fn disconnecting_either_side_cleans_up_relay_session() {
    let (_db, _registry, router, _task, ws_url) = spawn_test_server().await;

    let (mut phone, _) = connect_async(&ws_url).await.expect("connect phone");
    register_device(
        &mut phone,
        DeviceRegister {
            device_id: "alice-phone".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Phone as i32,
            display_name: "Alice Phone".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    let (mut agent, _) = connect_async(&ws_url).await.expect("connect agent");
    register_device(
        &mut agent,
        DeviceRegister {
            device_id: "alice-agent".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Agent as i32,
            display_name: "Alice Agent".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;

    send_envelope(
        &mut phone,
        Envelope {
            protocol_version: 1,
            request_id: "req-connect-cleanup".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::ConnectToDevice(ConnectToDevice {
                target_device_id: "alice-agent".into(),
            })),
        },
    )
    .await;
    let ack = recv_connect_ack(&mut phone).await;
    assert!(ack.success);
    assert!(router.session_for_phone("alice-phone").await.is_some());

    agent.close(None).await.expect("close agent");

    wait_for_session_cleanup(&router, "alice-phone").await;
}

async fn spawn_test_server() -> (
    Arc<Database>,
    Arc<DeviceRegistry>,
    Arc<SessionRouter>,
    JoinHandle<()>,
    String,
) {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert alice");
    db.insert_user("bob", "mrt_ak_bob1234567890abcdef")
        .expect("insert bob");

    let registry = Arc::new(DeviceRegistry::new(Arc::clone(&db)));
    let router = Arc::new(SessionRouter::new(Arc::clone(&registry)));
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let task = tokio::spawn({
        let registry = Arc::clone(&registry);
        let router = Arc::clone(&router);
        async move {
            server::serve(listener, registry, router)
                .await
                .expect("serve");
        }
    });

    (db, registry, router, task, format!("ws://{}/ws", addr))
}

async fn register_device(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    register: DeviceRegister,
) {
    send_device_register(socket, "req-register", register).await;
    let ack = recv_device_register_ack(socket).await;
    assert!(ack.success, "register failed: {}", ack.message);
}

async fn send_device_register(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    request_id: &str,
    register: DeviceRegister,
) {
    send_envelope(
        socket,
        Envelope {
            protocol_version: 1,
            request_id: request_id.into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::DeviceRegister(register)),
        },
    )
    .await;
}

async fn recv_device_register_ack(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> DeviceRegisterAck {
    match recv_envelope(socket).await.payload.expect("payload") {
        Payload::DeviceRegisterAck(value) => value,
        other => panic!("expected device register ack, got {other:?}"),
    }
}

async fn recv_device_list_response(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> DeviceListResponse {
    match recv_envelope(socket).await.payload.expect("payload") {
        Payload::DeviceListResponse(value) => value,
        other => panic!("expected device list response, got {other:?}"),
    }
}

async fn recv_connect_ack(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> proto_gen::ConnectToDeviceAck {
    match recv_envelope(socket).await.payload.expect("payload") {
        Payload::ConnectToDeviceAck(value) => value,
        other => panic!("expected connect ack, got {other:?}"),
    }
}

async fn send_envelope(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    envelope: Envelope,
) {
    socket
        .send(Message::Binary(encode_frame(&envelope).into()))
        .await
        .expect("send envelope");
}

async fn recv_envelope(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> Envelope {
    let frame = timeout(Duration::from_secs(1), socket.next())
        .await
        .expect("recv timeout")
        .expect("expected frame")
        .expect("websocket ok");

    match frame {
        Message::Binary(bytes) => decode_frame(&bytes),
        other => panic!("expected binary frame, got {other:?}"),
    }
}

fn encode_frame(envelope: &Envelope) -> Vec<u8> {
    let payload = envelope.encode_to_vec();
    let length = payload.len() as u32;
    let mut frame = Vec::with_capacity(payload.len() + 4);
    frame.extend_from_slice(&length.to_be_bytes());
    frame.extend_from_slice(&payload);
    frame
}

fn decode_frame(bytes: &[u8]) -> Envelope {
    let expected_len = u32::from_be_bytes(bytes[..4].try_into().expect("prefix")) as usize;
    assert_eq!(expected_len, bytes.len() - 4, "frame length mismatch");
    Envelope::decode(&bytes[4..]).expect("decode envelope")
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time")
        .as_millis() as u64
}

async fn wait_for_session_cleanup(router: &Arc<SessionRouter>, phone_id: &str) {
    for _ in 0..50 {
        if router.session_for_phone(phone_id).await.is_none() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }

    panic!("session for {phone_id} was not cleaned up");
}
