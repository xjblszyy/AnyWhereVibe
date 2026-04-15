use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use connection_node::db::Database;
use connection_node::registry::DeviceRegistry;
use connection_node::router::SessionRouter;
use connection_node::server;
use futures_util::{SinkExt, StreamExt};
use proto_gen::agent_event::Evt;
use proto_gen::envelope::Payload;
use proto_gen::{
    AgentEvent, ClientType, ConnectToDevice, ConnectToDeviceAck, DeviceInfo, DeviceListRequest,
    DeviceListResponse, DeviceRegister, DeviceRegisterAck, DeviceType, Envelope, Handshake,
    SessionListUpdate,
};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

#[tokio::test]
async fn register_with_connection_node_succeeds_and_device_is_listed() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let mut socket = agent::transport::connect_and_register_remote(
        &ws_url,
        "agent-macbook",
        "Ming's MacBook",
        "mrt_ak_alice1234567890abcd",
    )
    .await
    .expect("register remote transport");

    send_envelope(
        &mut socket,
        Envelope {
            protocol_version: 1,
            request_id: "req-device-list".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::DeviceListRequest(DeviceListRequest {})),
        },
    )
    .await;

    let response = recv_device_list_response(&mut socket).await;
    let devices: Vec<DeviceInfo> = response.devices;
    assert!(devices.iter().any(|device| device.device_id == "agent-macbook"));
}

#[tokio::test]
async fn register_with_connection_node_rejects_invalid_token() {
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let error = agent::transport::connect_and_register_remote(
        &ws_url,
        "agent-macbook",
        "Ming's MacBook",
        "mrt_ak_invalid",
    )
    .await
    .expect_err("invalid token should fail");

    assert!(
        error.to_string().contains("invalid auth token"),
        "unexpected error: {error:?}"
    );
}

#[tokio::test]
async fn remote_bridge_forwards_handshake_and_initial_session_list() {
    let agent_server = agent::test_support::spawn_mock_server().await;
    let (_db, _registry, _router, _task, ws_url) = spawn_test_server().await;

    let remote_socket = agent::transport::connect_and_register_remote(
        &ws_url,
        "alice-agent",
        "Alice Agent",
        "mrt_ak_alice1234567890abcd",
    )
    .await
    .expect("register agent");
    let local_server_url = agent_server.ws_url();
    let bridge_task = tokio::spawn(agent::transport::bridge_remote_socket_to_local_server(
        remote_socket,
        local_server_url,
    ));

    let (mut phone, _) = connect_async(&ws_url).await.expect("connect phone");
    send_device_register(
        &mut phone,
        "req-phone-register",
        DeviceRegister {
            device_id: "alice-phone".into(),
            auth_token: "mrt_ak_alice1234567890abcd".into(),
            device_type: DeviceType::Phone as i32,
            display_name: "Alice Phone".into(),
            agent_version: "1.0.0".into(),
        },
    )
    .await;
    let ack = recv_device_register_ack(&mut phone).await;
    assert!(ack.success);

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
    let connect_ack = recv_connect_ack(&mut phone).await;
    assert!(connect_ack.success, "connect failed: {}", connect_ack.message);

    send_envelope(
        &mut phone,
        Envelope {
            protocol_version: 1,
            request_id: "req-handshake".into(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Handshake(Handshake {
                protocol_version: 1,
                client_type: ClientType::PhoneAndroid as i32,
                client_version: "1.0.0".into(),
                device_id: "alice-phone".into(),
            })),
        },
    )
    .await;

    let mut saw_agent_info = false;
    let mut saw_session_list = false;
    for _ in 0..4 {
        let envelope = recv_envelope(&mut phone).await;
        match envelope.payload.expect("payload") {
            Payload::Event(AgentEvent {
                evt: Some(Evt::AgentInfo(_)),
            }) => saw_agent_info = true,
            Payload::Event(AgentEvent {
                evt: Some(Evt::SessionList(SessionListUpdate { sessions })),
            }) => {
                saw_session_list = sessions.iter().any(|session| session.name == "Main Session");
            }
            _ => {}
        }
        if saw_agent_info && saw_session_list {
            break;
        }
    }

    bridge_task.abort();
    assert!(saw_agent_info, "agent info was not relayed");
    assert!(saw_session_list, "initial session list was not relayed");
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

async fn send_envelope(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    envelope: Envelope,
) {
    socket
        .send(Message::Binary(
            agent::wire::encode_ws_binary_message(&envelope)
                .expect("encode envelope")
                .into(),
        ))
        .await
        .expect("send envelope");
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

async fn recv_connect_ack(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> ConnectToDeviceAck {
    match recv_envelope(socket).await.payload.expect("payload") {
        Payload::ConnectToDeviceAck(value) => value,
        other => panic!("expected connect ack, got {other:?}"),
    }
}

async fn recv_device_list_response(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> DeviceListResponse {
    let frame = timeout(Duration::from_secs(1), socket.next())
        .await
        .expect("recv timeout")
        .expect("expected frame")
        .expect("ws ok");

    match frame {
        Message::Binary(bytes) => {
            let envelope = agent::wire::decode_ws_binary_message(&bytes).expect("decode envelope");
            match envelope.payload.expect("payload") {
                Payload::DeviceListResponse(response) => response,
                other => panic!("expected device list response, got {other:?}"),
            }
        }
        other => panic!("expected binary frame, got {other:?}"),
    }
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
        .expect("ws ok");

    match frame {
        Message::Binary(bytes) => agent::wire::decode_ws_binary_message(&bytes).expect("decode envelope"),
        other => panic!("expected binary frame, got {other:?}"),
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time")
        .as_millis() as u64
}
