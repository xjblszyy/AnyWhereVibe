use std::collections::VecDeque;
use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use proto_gen::agent_command::Cmd;
use proto_gen::agent_event::Evt;
use proto_gen::envelope::Payload;
use proto_gen::session_control::Action;
use proto_gen::{
    AgentCommand, AgentEvent, AgentInfo, ApprovalRequest, ApprovalResponse, ClientType,
    CreateSession, Envelope, ErrorEvent, GetStatus, Handshake, Heartbeat, SendPrompt,
    SessionControl, SessionInfo, SessionListUpdate, TaskStatusUpdate,
};
use tempfile::TempDir;
use tokio::sync::{oneshot, Mutex};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};
use uuid::Uuid;

use crate::adapter::{AgentAdapter, MockAdapter};
use crate::server::Server;
use crate::session::SessionManager;
use crate::wire::{decode_ws_binary_message, encode_ws_binary_message};

pub type TestSocket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

pub struct SpawnedServer {
    ws_url: String,
    shutdown_tx: Option<oneshot::Sender<()>>,
    task: Option<tokio::task::JoinHandle<anyhow::Result<()>>>,
    _temp_dir: TempDir,
}

impl SpawnedServer {
    pub fn ws_url(&self) -> String {
        self.ws_url.clone()
    }
}

impl Drop for SpawnedServer {
    fn drop(&mut self) {
        if let Some(shutdown_tx) = self.shutdown_tx.take() {
            let _ = shutdown_tx.send(());
        }

        if let Some(task) = self.task.take() {
            task.abort();
        }
    }
}

pub async fn spawn_mock_server() -> SpawnedServer {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let sessions_path = temp_dir.path().join("sessions.json");

    let mut adapter = MockAdapter::new();
    adapter.start().await.expect("start mock adapter");
    let adapter: Arc<dyn AgentAdapter> = Arc::new(adapter);
    let sessions = Arc::new(Mutex::new(
        SessionManager::new(&sessions_path).expect("create session manager"),
    ));

    let server = Server::bind("127.0.0.1:0", adapter, sessions)
        .await
        .expect("bind test websocket server");
    let local_addr = server.local_addr().expect("read server address");
    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let task = tokio::spawn(async move { server.run(shutdown_rx).await });

    SpawnedServer {
        ws_url: format!("ws://127.0.0.1:{}/", local_addr.port()),
        shutdown_tx: Some(shutdown_tx),
        task: Some(task),
        _temp_dir: temp_dir,
    }
}

pub async fn recv_error_event(socket: &mut TestSocket) -> ErrorEvent {
    loop {
        let envelope = recv_envelope(socket).await;
        if let Some(Payload::Event(AgentEvent {
            evt: Some(Evt::Error(error)),
        })) = envelope.payload
        {
            return error;
        }
    }
}

pub async fn recv_agent_info(socket: &mut TestSocket) -> AgentInfo {
    loop {
        let envelope = recv_envelope(socket).await;
        if let Some(Payload::Event(AgentEvent {
            evt: Some(Evt::AgentInfo(info)),
        })) = envelope.payload
        {
            return info;
        }
    }
}

pub async fn send_valid_handshake(socket: &mut TestSocket) {
    send_handshake_with_protocol(socket, 1).await;
}

pub async fn send_handshake_with_protocol(socket: &mut TestSocket, version: u32) {
    send_test_envelope(
        socket,
        Envelope {
            protocol_version: version,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Handshake(Handshake {
                protocol_version: version,
                client_type: ClientType::PhoneIos as i32,
                client_version: "1.0.0".to_owned(),
                device_id: "test-ios".to_owned(),
            })),
        },
    )
    .await;
}

pub async fn send_first_message_status_request(socket: &mut TestSocket) {
    send_test_envelope(
        socket,
        Envelope {
            protocol_version: 1,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Command(AgentCommand {
                cmd: Some(Cmd::GetStatus(GetStatus {
                    session_id: String::new(),
                })),
            })),
        },
    )
    .await;
}

pub async fn expect_socket_closed(socket: &mut TestSocket) -> bool {
    matches!(
        timeout(Duration::from_secs(2), socket.next()).await,
        Ok(Some(Ok(Message::Close(_)))) | Ok(None)
    )
}

pub struct TestClient {
    socket: TestSocket,
    buffered: VecDeque<Envelope>,
}

impl TestClient {
    pub async fn connect(url: String) -> Self {
        let (socket, _) = connect_async(url).await.expect("connect websocket client");
        Self {
            socket,
            buffered: VecDeque::new(),
        }
    }

    pub async fn handshake_ios(&mut self) {
        send_valid_handshake(&mut self.socket).await;
        let _ = recv_agent_info(&mut self.socket).await;
    }

    pub async fn create_session(&mut self, name: &str, working_dir: &str) -> SessionInfo {
        self.send_envelope(Envelope {
            protocol_version: 1,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Session(SessionControl {
                action: Some(Action::Create(CreateSession {
                    name: name.to_owned(),
                    working_dir: working_dir.to_owned(),
                })),
            })),
        })
        .await;

        let mut skipped = Vec::new();
        loop {
            let envelope = self.next_envelope().await;
            match &envelope.payload {
                Some(Payload::Event(AgentEvent {
                    evt: Some(Evt::SessionList(update)),
                })) => {
                    if let Some(session) = update
                        .sessions
                        .iter()
                        .find(|session| session.name == name && session.working_dir == working_dir)
                        .cloned()
                    {
                        for skipped_envelope in skipped {
                            self.buffered.push_back(skipped_envelope);
                        }
                        self.buffered.push_back(envelope);
                        return session;
                    }

                    skipped.push(envelope);
                }
                _ => skipped.push(envelope),
            }
        }
    }

    pub async fn expect_session_list_update(&mut self) -> SessionListUpdate {
        loop {
            let envelope = self.next_envelope().await;
            if let Some(Payload::Event(AgentEvent {
                evt: Some(Evt::SessionList(update)),
            })) = envelope.payload
            {
                return update;
            }
        }
    }

    pub async fn send_prompt(&mut self, session_id: &str, prompt: &str) {
        self.send_envelope(Envelope {
            protocol_version: 1,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Command(AgentCommand {
                cmd: Some(Cmd::SendPrompt(SendPrompt {
                    session_id: session_id.to_owned(),
                    prompt: prompt.to_owned(),
                })),
            })),
        })
        .await;
    }

    pub async fn send_prompt_expect_error(&mut self, session_id: &str, prompt: &str) -> ErrorEvent {
        self.send_prompt(session_id, prompt).await;
        self.expect_error().await
    }

    pub async fn expect_approval_request(&mut self) -> ApprovalRequest {
        loop {
            let envelope = self.next_envelope().await;
            if let Some(Payload::Event(AgentEvent {
                evt: Some(Evt::ApprovalRequest(approval)),
            })) = envelope.payload
            {
                return approval;
            }
        }
    }

    pub async fn respond_approval(&mut self, approval_id: &str, approved: bool) {
        self.send_envelope(Envelope {
            protocol_version: 1,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Command(AgentCommand {
                cmd: Some(Cmd::ApprovalResponse(ApprovalResponse {
                    approval_id: approval_id.to_owned(),
                    approved,
                })),
            })),
        })
        .await;
    }

    pub async fn respond_approval_expect_error(
        &mut self,
        approval_id: &str,
        approved: bool,
    ) -> ErrorEvent {
        self.respond_approval(approval_id, approved).await;
        self.expect_error().await
    }

    pub async fn expect_status_sequence(&mut self, expected: &[&str]) {
        let mut matched = 0usize;
        while matched < expected.len() {
            let envelope = self.next_envelope().await;
            if let Some(Payload::Event(AgentEvent {
                evt: Some(Evt::StatusUpdate(TaskStatusUpdate { status, .. })),
            })) = envelope.payload
            {
                let name = task_status_name(status);
                if name == expected[matched] {
                    matched += 1;
                }
            }
        }
    }

    pub async fn expect_connection_alive(&mut self) {
        self.send_envelope(Envelope {
            protocol_version: 1,
            request_id: new_request_id(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Heartbeat(Heartbeat {
                timestamp_ms: now_ms(),
            })),
        })
        .await;

        if let Ok(Some(message)) = timeout(Duration::from_millis(100), self.socket.next()).await {
            match message.expect("websocket read should succeed") {
                Message::Close(_) => panic!("connection should remain open"),
                Message::Binary(bytes) => {
                    let envelope = decode_ws_binary_message(&bytes).expect("decode envelope");
                    if !matches!(envelope.payload, Some(Payload::Heartbeat(_))) {
                        self.buffered.push_back(envelope);
                    }
                }
                _ => {}
            }
        }
    }

    pub async fn expect_disconnect(&mut self) {
        loop {
            match self.socket.next().await {
                Some(Ok(Message::Close(_))) | None => return,
                Some(Ok(Message::Binary(bytes))) => {
                    let envelope = decode_ws_binary_message(&bytes).expect("decode envelope");
                    self.buffered.push_back(envelope);
                }
                Some(Ok(_)) => {}
                Some(Err(error)) => panic!("websocket read failed: {error}"),
            }
        }
    }

    async fn expect_error(&mut self) -> ErrorEvent {
        loop {
            let envelope = self.next_envelope().await;
            if let Some(Payload::Event(AgentEvent {
                evt: Some(Evt::Error(error)),
            })) = envelope.payload
            {
                return error;
            }
        }
    }

    async fn next_envelope(&mut self) -> Envelope {
        if let Some(envelope) = self.buffered.pop_front() {
            return envelope;
        }

        recv_envelope(&mut self.socket).await
    }

    async fn send_envelope(&mut self, envelope: Envelope) {
        send_test_envelope(&mut self.socket, envelope).await;
    }
}

async fn send_test_envelope(socket: &mut TestSocket, envelope: Envelope) {
    let frame = encode_ws_binary_message(&envelope).expect("encode websocket frame");
    socket
        .send(Message::Binary(frame.into()))
        .await
        .expect("send websocket frame");
}

async fn recv_envelope(socket: &mut TestSocket) -> Envelope {
    loop {
        let message = socket
            .next()
            .await
            .expect("websocket should remain open")
            .expect("websocket frame should decode");

        match message {
            Message::Binary(bytes) => {
                return decode_ws_binary_message(&bytes).expect("decode envelope")
            }
            Message::Close(_) => panic!("expected envelope but socket closed"),
            Message::Ping(_) | Message::Pong(_) => continue,
            other => panic!("unexpected websocket message: {other:?}"),
        }
    }
}

fn new_request_id() -> String {
    Uuid::new_v4().to_string()
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock should be after unix epoch")
        .as_millis() as u64
}

fn task_status_name(status: i32) -> &'static str {
    match proto_gen::TaskStatus::try_from(status) {
        Ok(proto_gen::TaskStatus::Idle) => "IDLE",
        Ok(proto_gen::TaskStatus::Running) => "RUNNING",
        Ok(proto_gen::TaskStatus::WaitingApproval) => "WAITING_APPROVAL",
        Ok(proto_gen::TaskStatus::Completed) => "COMPLETED",
        Ok(proto_gen::TaskStatus::Error) => "ERROR",
        Ok(proto_gen::TaskStatus::Cancelled) => "CANCELLED",
        _ => "UNKNOWN",
    }
}
