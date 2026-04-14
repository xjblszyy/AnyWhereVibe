use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use futures_util::stream::SplitSink;
use futures_util::{Sink, SinkExt, StreamExt};
use proto_gen::agent_command::Cmd;
use proto_gen::agent_event::Evt;
use proto_gen::envelope::Payload;
use proto_gen::session_control::Action;
use proto_gen::{
    AgentEvent, AgentInfo, ApprovalResponse, CancelTask, CreateSession, Envelope, ErrorEvent,
    GetStatus, Heartbeat, SendPrompt, SessionInfo, SessionListUpdate, TaskStatus,
};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, oneshot, Mutex};
use tokio::time::{self, Duration, Instant, MissedTickBehavior};
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::http::{Response as HttpResponse, StatusCode};
use tokio_tungstenite::tungstenite::{self, Message};
use tokio_tungstenite::{accept_hdr_async, WebSocketStream};
use tracing::{debug, warn};
use uuid::Uuid;

use crate::adapter::AgentAdapter;
use crate::session::SessionManager;
use crate::wire::{decode_ws_binary_message, encode_ws_binary_message};

const PROTOCOL_VERSION: u32 = 1;
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(15);
const IDLE_TIMEOUT: Duration = Duration::from_secs(45);

type WsWrite = SplitSink<WebSocketStream<TcpStream>, Message>;
#[derive(Clone)]
struct ServerState {
    adapter: Arc<dyn AgentAdapter>,
    sessions: Arc<Mutex<SessionManager>>,
    outbound: broadcast::Sender<Envelope>,
    agent_info: AgentInfo,
}

pub struct Server {
    listener: TcpListener,
    state: ServerState,
}

impl Server {
    pub async fn bind(
        listen_addr: &str,
        adapter: Arc<dyn AgentAdapter>,
        sessions: Arc<Mutex<SessionManager>>,
    ) -> Result<Self> {
        let listener = TcpListener::bind(listen_addr)
            .await
            .with_context(|| format!("failed to bind websocket server to {listen_addr}"))?;
        let (outbound, _) = broadcast::channel(256);

        Ok(Self {
            listener,
            state: ServerState {
                agent_info: AgentInfo {
                    agent_version: env!("CARGO_PKG_VERSION").to_owned(),
                    adapter_type: adapter.name().to_owned(),
                    hostname: hostname(),
                    os: std::env::consts::OS.to_owned(),
                },
                adapter,
                sessions,
                outbound,
            },
        })
    }

    pub fn local_addr(&self) -> Result<SocketAddr> {
        self.listener
            .local_addr()
            .context("failed to read bound websocket server address")
    }

    pub async fn run(self, mut shutdown: oneshot::Receiver<()>) -> Result<()> {
        let adapter_forward_state = self.state.clone();
        let adapter_forwarder = tokio::spawn(async move {
            if let Err(error) = forward_adapter_events(adapter_forward_state).await {
                warn!(?error, "adapter event forwarder stopped");
            }
        });

        loop {
            tokio::select! {
                _ = &mut shutdown => {
                    debug!("websocket server shutdown requested");
                    break;
                }
                accepted = self.listener.accept() => {
                    let (stream, peer_addr) = accepted.context("failed to accept websocket connection")?;
                    let state = self.state.clone();
                    tokio::spawn(async move {
                        if let Err(error) = handle_connection(stream, state).await {
                            warn!(?peer_addr, ?error, "websocket connection failed");
                        }
                    });
                }
            }
        }

        adapter_forwarder.abort();
        Ok(())
    }
}

async fn forward_adapter_events(state: ServerState) -> Result<()> {
    let mut rx = state.adapter.subscribe();

    loop {
        let event = match rx.recv().await {
            Ok(event) => event,
            Err(broadcast::error::RecvError::Lagged(_)) => continue,
            Err(broadcast::error::RecvError::Closed) => break,
        };

        if let Some(Evt::StatusUpdate(update)) = &event.evt {
            let mut sessions = state.sessions.lock().await;
            if sessions.get(&update.session_id).is_some() {
                if let Ok(status) = TaskStatus::try_from(update.status) {
                    let _ = sessions.update_status(&update.session_id, status);
                }
                let session_list = sessions.list();
                drop(sessions);
                broadcast_session_list(&state, session_list);
            }
        }

        broadcast_event(&state, event);
    }

    Ok(())
}

async fn handle_connection(stream: TcpStream, state: ServerState) -> Result<()> {
    let websocket = accept_websocket(stream).await?;
    let (mut write, mut read) = websocket.split();

    let handshake_envelope = loop {
        let Some(message) = read
            .next()
            .await
            .transpose()
            .context("failed to read websocket frame")?
        else {
            return Ok(());
        };

        match parse_incoming_message(&mut write, message).await? {
            IncomingFrame::Envelope(envelope) => break envelope,
            IncomingFrame::Closed => return Ok(()),
            IncomingFrame::Ignored => continue,
        }
    };

    let Some(Payload::Handshake(handshake)) = handshake_envelope.payload.clone() else {
        send_error_and_close(
            &mut write,
            "PROTOCOL_ERROR",
            "handshake is required as the first message",
            true,
            &handshake_envelope.request_id,
        )
        .await?;
        return Ok(());
    };

    if !validate_envelope_protocol_version(&mut write, &handshake_envelope).await? {
        return Ok(());
    }

    if handshake.protocol_version != PROTOCOL_VERSION {
        send_error_and_close(
            &mut write,
            "VERSION_MISMATCH",
            format!(
                "client protocol version {} does not match server version {}",
                handshake.protocol_version, PROTOCOL_VERSION
            ),
            true,
            &handshake_envelope.request_id,
        )
        .await?;
        return Ok(());
    }

    send_event(
        &mut write,
        &handshake_envelope.request_id,
        AgentEvent {
            evt: Some(Evt::AgentInfo(state.agent_info.clone())),
        },
    )
    .await?;

    let mut outbound_rx = state.outbound.subscribe();
    let mut heartbeat = time::interval_at(Instant::now() + HEARTBEAT_INTERVAL, HEARTBEAT_INTERVAL);
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);
    let mut idle_deadline = Instant::now() + IDLE_TIMEOUT;

    loop {
        let idle_sleep = time::sleep_until(idle_deadline);
        tokio::pin!(idle_sleep);

        tokio::select! {
            _ = heartbeat.tick() => {
                send_envelope(
                    &mut write,
                    Envelope {
                        protocol_version: PROTOCOL_VERSION,
                        request_id: new_request_id(),
                        timestamp_ms: now_ms(),
                        payload: Some(Payload::Heartbeat(Heartbeat {
                            timestamp_ms: now_ms(),
                        })),
                    }
                ).await?;
            }
            received = outbound_rx.recv() => {
                match received {
                    Ok(envelope) => send_envelope(&mut write, envelope).await?,
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => return Ok(()),
                }
            }
            next_message = read.next() => {
                let Some(message) = next_message.transpose().context("failed to read websocket frame")? else {
                    return Ok(());
                };

                match parse_incoming_message(&mut write, message).await? {
                    IncomingFrame::Envelope(envelope) => {
                        if !validate_envelope_protocol_version(&mut write, &envelope).await? {
                            return Ok(());
                        }
                        idle_deadline = Instant::now() + IDLE_TIMEOUT;
                        let should_close = route_envelope(&state, &mut write, envelope).await?;
                        if should_close {
                            return Ok(());
                        }
                    }
                    IncomingFrame::Closed => return Ok(()),
                    IncomingFrame::Ignored => {}
                }
            }
            _ = &mut idle_sleep => {
                let _ = write.send(Message::Close(None)).await;
                return Ok(());
            }
        }
    }
}

async fn accept_websocket(stream: TcpStream) -> Result<WebSocketStream<TcpStream>> {
    accept_hdr_async(stream, |request: &Request, response: Response| {
        if request.uri().path() == "/" {
            Ok(response)
        } else {
            Err(HttpResponse::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Some("not found".to_owned()))
                .expect("response should build"))
        }
    })
    .await
    .context("websocket upgrade failed")
}

async fn route_envelope(
    state: &ServerState,
    write: &mut WsWrite,
    envelope: Envelope,
) -> Result<bool> {
    match envelope.payload {
        Some(Payload::Heartbeat(_)) => Ok(false),
        Some(Payload::Command(command)) => {
            if let Some(cmd) = command.cmd {
                route_command(state, write, envelope.request_id, cmd).await?;
            } else {
                send_error_and_close(
                    write,
                    "PROTOCOL_ERROR",
                    "command envelope did not include a command payload",
                    true,
                    &envelope.request_id,
                )
                .await?;
                return Ok(true);
            }

            Ok(false)
        }
        Some(Payload::Session(control)) => {
            if let Some(action) = control.action {
                route_session_control(state, write, envelope.request_id, action).await?;
            } else {
                send_error_and_close(
                    write,
                    "PROTOCOL_ERROR",
                    "session envelope did not include an action payload",
                    true,
                    &envelope.request_id,
                )
                .await?;
                return Ok(true);
            }

            Ok(false)
        }
        _ => {
            send_error_and_close(
                write,
                "PROTOCOL_ERROR",
                "unsupported envelope payload for websocket runtime",
                true,
                &envelope.request_id,
            )
            .await?;
            Ok(true)
        }
    }
}

async fn route_command(
    state: &ServerState,
    write: &mut WsWrite,
    request_id: String,
    cmd: Cmd,
) -> Result<()> {
    match cmd {
        Cmd::SendPrompt(SendPrompt { session_id, prompt }) => {
            let prompt_decision = {
                let mut sessions = state.sessions.lock().await;

                if sessions.get(&session_id).is_none() {
                    PromptDecision::MissingSession
                } else if sessions.list().into_iter().any(|session| {
                    session.status == TaskStatus::Running as i32
                        || session.status == TaskStatus::WaitingApproval as i32
                }) {
                    PromptDecision::Busy
                } else {
                    sessions.update_status(&session_id, TaskStatus::Running)?;
                    PromptDecision::Accepted(sessions.list())
                }
            };

            match prompt_decision {
                PromptDecision::MissingSession => {
                    send_error(
                        write,
                        &request_id,
                        "SESSION_NOT_FOUND",
                        format!("session '{session_id}' does not exist"),
                        false,
                    )
                    .await?;
                    return Ok(());
                }
                PromptDecision::Busy => {
                    send_error(
                        write,
                        &request_id,
                        "TASK_ALREADY_RUNNING",
                        "another task is already running",
                        false,
                    )
                    .await?;
                    return Ok(());
                }
                PromptDecision::Accepted(session_list) => {
                    broadcast_session_list(state, session_list);
                }
            }

            if let Err(error) = state.adapter.send_prompt(&session_id, &prompt).await {
                let mut sessions = state.sessions.lock().await;
                let _ = sessions.update_status(&session_id, TaskStatus::Idle);
                let session_list = sessions.list();
                drop(sessions);
                broadcast_session_list(state, session_list);

                send_error(
                    write,
                    &request_id,
                    "ADAPTER_ERROR",
                    error.to_string(),
                    false,
                )
                .await?;
            }
        }
        Cmd::ApprovalResponse(ApprovalResponse {
            approval_id,
            approved,
        }) => {
            if let Err(_error) = state.adapter.respond_approval(&approval_id, approved).await {
                send_error(
                    write,
                    &request_id,
                    "APPROVAL_NOT_FOUND",
                    format!("approval '{approval_id}' does not exist"),
                    false,
                )
                .await?;
            }
        }
        Cmd::CancelTask(CancelTask { session_id }) => {
            let exists = {
                let sessions = state.sessions.lock().await;
                sessions.get(&session_id).is_some()
            };
            if !exists {
                send_error(
                    write,
                    &request_id,
                    "SESSION_NOT_FOUND",
                    format!("session '{session_id}' does not exist"),
                    false,
                )
                .await?;
                return Ok(());
            }

            if let Err(error) = state.adapter.cancel_task(&session_id).await {
                send_error(
                    write,
                    &request_id,
                    "ADAPTER_ERROR",
                    error.to_string(),
                    false,
                )
                .await?;
            }
        }
        Cmd::GetStatus(GetStatus { session_id }) => {
            let sessions = state.sessions.lock().await;
            let filtered = if session_id.is_empty() {
                sessions.list()
            } else {
                sessions
                    .list()
                    .into_iter()
                    .filter(|session| session.session_id == session_id)
                    .collect()
            };
            drop(sessions);

            send_event(
                write,
                &request_id,
                AgentEvent {
                    evt: Some(Evt::SessionList(SessionListUpdate { sessions: filtered })),
                },
            )
            .await?;
        }
    }

    Ok(())
}

async fn validate_envelope_protocol_version(
    write: &mut WsWrite,
    envelope: &Envelope,
) -> Result<bool> {
    if envelope.protocol_version == PROTOCOL_VERSION {
        return Ok(true);
    }

    send_error_and_close(
        write,
        "VERSION_MISMATCH",
        format!(
            "client envelope protocol version {} does not match server version {}",
            envelope.protocol_version, PROTOCOL_VERSION
        ),
        true,
        &envelope.request_id,
    )
    .await?;
    Ok(false)
}

async fn route_session_control(
    state: &ServerState,
    write: &mut WsWrite,
    request_id: String,
    action: Action,
) -> Result<()> {
    match action {
        Action::Create(CreateSession { name, working_dir }) => {
            let session_list = {
                let mut sessions = state.sessions.lock().await;
                sessions.create(&name, &working_dir)?;
                sessions.list()
            };

            let _ = request_id;
            broadcast_session_list(state, session_list);
        }
        Action::List(_) => {
            let session_list = state.sessions.lock().await.list();
            send_event(
                write,
                &request_id,
                AgentEvent {
                    evt: Some(Evt::SessionList(SessionListUpdate {
                        sessions: session_list,
                    })),
                },
            )
            .await?;
        }
        _ => {
            send_error(
                write,
                &request_id,
                "NOT_IMPLEMENTED",
                "this session action is not implemented in the A-slice",
                false,
            )
            .await?;
        }
    }

    Ok(())
}

fn broadcast_event(state: &ServerState, event: AgentEvent) {
    let _ = state.outbound.send(Envelope {
        protocol_version: PROTOCOL_VERSION,
        request_id: new_request_id(),
        timestamp_ms: now_ms(),
        payload: Some(Payload::Event(event)),
    });
}

fn broadcast_session_list(state: &ServerState, sessions: Vec<SessionInfo>) {
    broadcast_event(
        state,
        AgentEvent {
            evt: Some(Evt::SessionList(SessionListUpdate { sessions })),
        },
    );
}

async fn parse_incoming_message(write: &mut WsWrite, message: Message) -> Result<IncomingFrame> {
    match message {
        Message::Binary(bytes) => match decode_ws_binary_message(&bytes) {
            Ok(envelope) => Ok(IncomingFrame::Envelope(envelope)),
            Err(error) => {
                send_error_and_close(
                    write,
                    "PROTOCOL_ERROR",
                    format!("failed to decode websocket frame: {error}"),
                    true,
                    &new_request_id(),
                )
                .await?;
                Ok(IncomingFrame::Closed)
            }
        },
        Message::Text(_) => {
            send_error_and_close(
                write,
                "PROTOCOL_ERROR",
                "text websocket frames are not supported",
                true,
                &new_request_id(),
            )
            .await?;
            Ok(IncomingFrame::Closed)
        }
        Message::Close(_) => Ok(IncomingFrame::Closed),
        Message::Ping(_) | Message::Pong(_) => Ok(IncomingFrame::Ignored),
        _ => Ok(IncomingFrame::Ignored),
    }
}

async fn send_envelope<S>(write: &mut S, envelope: Envelope) -> Result<()>
where
    S: Sink<Message, Error = tungstenite::Error> + Unpin,
{
    let frame = encode_ws_binary_message(&envelope)?;
    write
        .send(Message::Binary(frame.into()))
        .await
        .context("failed to send websocket binary frame")
}

async fn send_event<S>(write: &mut S, request_id: &str, event: AgentEvent) -> Result<()>
where
    S: Sink<Message, Error = tungstenite::Error> + Unpin,
{
    send_envelope(
        write,
        Envelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: request_id.to_owned(),
            timestamp_ms: now_ms(),
            payload: Some(Payload::Event(event)),
        },
    )
    .await
}

async fn send_error<S>(
    write: &mut S,
    request_id: &str,
    code: &str,
    message: impl Into<String>,
    fatal: bool,
) -> Result<()>
where
    S: Sink<Message, Error = tungstenite::Error> + Unpin,
{
    send_event(
        write,
        request_id,
        AgentEvent {
            evt: Some(Evt::Error(ErrorEvent {
                code: code.to_owned(),
                message: message.into(),
                fatal,
            })),
        },
    )
    .await
}

async fn send_error_and_close<S>(
    write: &mut S,
    code: &str,
    message: impl Into<String>,
    fatal: bool,
    request_id: &str,
) -> Result<()>
where
    S: Sink<Message, Error = tungstenite::Error> + Unpin,
{
    send_error(write, request_id, code, message, fatal).await?;
    write
        .send(Message::Close(None))
        .await
        .context("failed to close websocket connection")
}

fn hostname() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "unknown".to_owned())
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after unix epoch")
        .as_millis() as u64
}

fn new_request_id() -> String {
    Uuid::new_v4().to_string()
}

enum IncomingFrame {
    Envelope(Envelope),
    Closed,
    Ignored,
}

enum PromptDecision {
    MissingSession,
    Busy,
    Accepted(Vec<SessionInfo>),
}
