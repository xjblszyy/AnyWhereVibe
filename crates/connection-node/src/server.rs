use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::IntoResponse;
use axum::{routing::get, Router};
use futures_util::{SinkExt, StreamExt};
use prost::Message as ProstMessage;
use proto_gen::envelope::Payload;
use proto_gen::{
    ConnectToDeviceAck, ConnectionType, DeviceListResponse, DeviceRegisterAck, Envelope,
};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch};
use tower_http::trace::TraceLayer;
use tracing::info;

use crate::config::AppConfig;
use crate::registry::DeviceRegistry;
use crate::router::SessionRouter;

#[derive(Clone)]
struct AppState {
    registry: Arc<DeviceRegistry>,
    router: Arc<SessionRouter>,
}

pub async fn run(
    config: &AppConfig,
    registry: Arc<DeviceRegistry>,
    router: Arc<SessionRouter>,
) -> Result<()> {
    let (listener, _actual_addr) = bind_listener(&config.server.listen_addr).await?;
    serve(listener, registry, router).await
}

pub async fn serve(
    listener: TcpListener,
    registry: Arc<DeviceRegistry>,
    router: Arc<SessionRouter>,
) -> Result<()> {
    let actual_addr = listener.local_addr()?;
    let app = app(AppState { registry, router });
    info!("listening on {}", actual_addr);
    axum::serve(listener, app).await?;
    Ok(())
}

fn app(state: AppState) -> Router {
    Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health))
        .with_state(state)
        .layer(TraceLayer::new_for_http())
}

async fn health() -> &'static str {
    "ok"
}

async fn ws_handler(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_ws(socket, state))
}

async fn handle_ws(socket: WebSocket, state: AppState) {
    let (mut ws_tx, mut ws_rx) = socket.split();
    let (send_tx, mut send_rx) = mpsc::channel::<Vec<u8>>(256);
    let (close_tx, mut close_rx) = watch::channel(false);
    let writer_task = tokio::spawn(async move {
        loop {
            let Some(frame) = send_rx.recv().await else {
                if *close_rx.borrow() {
                    let _ = ws_tx.send(Message::Close(None)).await;
                }
                break;
            };

            if ws_tx.send(Message::Binary(frame.into())).await.is_err() {
                break;
            }

            if close_rx.has_changed().unwrap_or(false) {
                let _ = close_rx.borrow_and_update();
                if send_rx.is_closed() && send_rx.is_empty() && *close_rx.borrow() {
                    let _ = ws_tx.send(Message::Close(None)).await;
                    break;
                }
            }
        }
    });

    let Some(first_message) = ws_rx.next().await else {
        let _ = close_tx.send(true);
        drop(send_tx);
        let _ = writer_task.await;
        return;
    };

    let Ok(first_message) = first_message else {
        let _ = close_tx.send(true);
        drop(send_tx);
        let _ = writer_task.await;
        return;
    };

    let Some((request_id, register)) = decode_register_message(first_message) else {
        let _ = close_tx.send(true);
        drop(send_tx);
        let _ = writer_task.await;
        return;
    };

    let user_id = match state
        .registry
        .active_user_id_for_token(&register.auth_token)
    {
        Ok(Some(user_id)) => user_id,
        Ok(None) => {
            let ack = DeviceRegisterAck {
                success: false,
                message: "invalid auth token".to_string(),
            };
            let _ = send_envelope(
                &send_tx,
                response_envelope(request_id, Payload::DeviceRegisterAck(ack)),
            )
            .await;
            let _ = close_tx.send(true);
            drop(send_tx);
            let _ = writer_task.await;
            return;
        }
        Err(_) => {
            let _ = close_tx.send(true);
            drop(send_tx);
            let _ = writer_task.await;
            return;
        }
    };

    let register_device_id = register.device_id.clone();
    let register_result = state.registry.register(register, send_tx.clone()).await;
    let register_ack = match register_result {
        Ok(ack) => ack,
        Err(error) => DeviceRegisterAck {
            success: false,
            message: error.to_string(),
        },
    };
    let _ = send_envelope(
        &send_tx,
        response_envelope(request_id, Payload::DeviceRegisterAck(register_ack.clone())),
    )
    .await;
    if !register_ack.success {
        let _ = close_tx.send(true);
        drop(send_tx);
        let _ = writer_task.await;
        return;
    }

    while let Some(next_message) = ws_rx.next().await {
        let Ok(message) = next_message else {
            break;
        };

        match message {
            Message::Binary(bytes) => {
                if let Ok(envelope) = decode_ws_binary_message(&bytes) {
                    match envelope.payload {
                        Some(Payload::DeviceListRequest(_)) => {
                            let response = DeviceListResponse {
                                devices: state.registry.list_devices_for_user(user_id).await,
                            };
                            let _ = send_envelope(
                                &send_tx,
                                response_envelope(
                                    envelope.request_id,
                                    Payload::DeviceListResponse(response),
                                ),
                            )
                            .await;
                            continue;
                        }
                        Some(Payload::ConnectToDevice(request)) => {
                            let ack = match state
                                .router
                                .connect(&register_device_id, &request.target_device_id)
                                .await
                            {
                                Ok(ack) => ack,
                                Err(error) => ConnectToDeviceAck {
                                    success: false,
                                    message: error.to_string(),
                                    connection_type: ConnectionType::Unspecified as i32,
                                },
                            };
                            let _ = send_envelope(
                                &send_tx,
                                response_envelope(
                                    envelope.request_id,
                                    Payload::ConnectToDeviceAck(ack),
                                ),
                            )
                            .await;
                            continue;
                        }
                        _ => {}
                    }
                }

                if state
                    .router
                    .route(&register_device_id, bytes.to_vec())
                    .await
                    .is_err()
                {
                    break;
                }
            }
            Message::Close(_) => break,
            Message::Text(_) => break,
            Message::Ping(_) | Message::Pong(_) => {}
        }
    }

    state.router.disconnect(&register_device_id).await;
    let _ = state
        .registry
        .unregister(user_id, &register_device_id)
        .await;
    let _ = close_tx.send(true);
    drop(send_tx);
    let _ = writer_task.await;
}

async fn bind_listener(listen_addr: &str) -> Result<(TcpListener, SocketAddr)> {
    let listener = TcpListener::bind(listen_addr)
        .await
        .with_context(|| format!("failed to bind server listener at {listen_addr}"))?;
    let actual_addr = listener.local_addr()?;
    Ok((listener, actual_addr))
}

fn decode_register_message(message: Message) -> Option<(String, proto_gen::DeviceRegister)> {
    let Message::Binary(bytes) = message else {
        return None;
    };

    let envelope = decode_ws_binary_message(&bytes).ok()?;
    let request_id = envelope.request_id.clone();
    match envelope.payload {
        Some(Payload::DeviceRegister(register)) => Some((request_id, register)),
        _ => None,
    }
}

async fn send_envelope(send_tx: &mpsc::Sender<Vec<u8>>, envelope: Envelope) -> Result<()> {
    send_tx
        .send(encode_ws_binary_message(&envelope)?)
        .await
        .map_err(|_| anyhow::anyhow!("websocket writer channel closed"))?;
    Ok(())
}

fn encode_ws_binary_message(envelope: &Envelope) -> Result<Vec<u8>> {
    let payload = envelope.encode_to_vec();
    let length = payload.len() as u32;
    let mut frame = Vec::with_capacity(payload.len() + 4);
    frame.extend_from_slice(&length.to_be_bytes());
    frame.extend_from_slice(&payload);
    Ok(frame)
}

fn decode_ws_binary_message(bytes: &[u8]) -> Result<Envelope> {
    if bytes.len() < 4 {
        bail!("binary frame must include a 4-byte big-endian length prefix");
    }

    let expected_len = u32::from_be_bytes(bytes[..4].try_into()?) as usize;
    let payload = &bytes[4..];
    if payload.len() != expected_len {
        bail!(
            "binary frame length prefix {} does not match payload length {}",
            expected_len,
            payload.len()
        );
    }

    Ok(Envelope::decode(payload)?)
}

fn response_envelope(request_id: String, payload: Payload) -> Envelope {
    Envelope {
        protocol_version: 1,
        request_id,
        timestamp_ms: now_ms(),
        payload: Some(payload),
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time before unix epoch")
        .as_millis() as u64
}
